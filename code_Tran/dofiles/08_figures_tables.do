*==============================================================================
* 08_figures_tables.do  --  Summary stats and four descriptive figures
*------------------------------------------------------------------------------
* SAMPLE TOGGLE (mirrors 07_build_panel.do)
*   global fig_sample_mode controls which panel is used and how outputs are
*   named. Set before calling (00_master.do sets it, calling this file twice).
*     "expanded" -> core_affordability_panel_expanded_Tran.dta -> *_Tran.* (36 CMAs)
*     "baseline" -> core_affordability_panel_Tran.dta          -> *_baseline31_Tran.*
*------------------------------------------------------------------------------
* Output (36-CMA, the default this pipeline uses):
*   $output/summary_stats_presentation.xlsx
*   $output/fig1_gap_by_exposure_tercile_Tran.png ... fig4_..., qual_rate_path.png
*   $output/Graph_Log_affordability_gap_over_time_Tran.pdf
*==============================================================================

if "$fig_sample_mode" == "" global fig_sample_mode "baseline"

if "$fig_sample_mode" == "expanded" {
    capture confirm file "$clean/core_affordability_panel_expanded_Tran.dta"
    if _rc {
        display as error "Expanded panel not found; run 07_build_panel.do (expanded) first. Falling back to baseline."
        global fig_sample_mode "baseline"
    }
}

if "$fig_sample_mode" == "expanded" {
    global panel_in   "$clean/core_affordability_panel_expanded_Tran.dta"
    global fig_suffix ""
    global fig_nmkt    "36"
}
else {
    global panel_in   "$clean/core_affordability_panel_Tran.dta"
    global fig_suffix "_baseline31"
    global fig_nmkt    "31"
}
display as text "Building figures/tables in fig_sample_mode = $fig_sample_mode"

* -------------------------- Summary stats -----------------------------------
use "$panel_in", clear

local vars benchmark_price median_income contract_rate_5yr qual_rate ///
           max_qualified_price affordability_gap affordability_gap_pct ///
           price_income_ratio pre_exposure_z

tempname memhold
tempfile summary_stats
postfile `memhold' str40 variable double N mean sd min p50 max ///
    using `summary_stats', replace
foreach v of local vars {
    quietly summ `v', detail
    post `memhold' ("`v'") (r(N)) (r(mean)) (r(sd)) ///
        (r(min)) (r(p50)) (r(max))
}
postclose `memhold'

use `summary_stats', clear
export excel using "$output/summary_stats_presentation${fig_suffix}.xlsx", ///
    firstrow(variables) replace
list, noobs


* -------------------------- Fig 1: gap by tercile ---------------------------
use "$panel_in", clear
preserve
    collapse (mean) mean_gap = affordability_gap, by(year exposure_tercile)
    twoway ///
        (line mean_gap year if exposure_tercile == 1, sort) ///
        (line mean_gap year if exposure_tercile == 2, sort) ///
        (line mean_gap year if exposure_tercile == 3, sort), ///
        xline(2022, lpattern(dash)) yline(0, lpattern(dot)) ///
        legend(order(1 "Low pre-exposure" 2 "Middle pre-exposure" 3 "High pre-exposure")) ///
        title("Affordability Gap Over Time by Pre-2022 Exposure") ///
        subtitle("$fig_nmkt Canadian CMAs, T1FF median family income, 2016-2023") ///
        xtitle("Year") ytitle("Average affordability gap") ///
        graphregion(color(white))
    graph export "$output/fig1_gap_by_exposure_tercile${fig_suffix}_Tran.png", replace width(2400)
restore


* -------------------------- Fig 2: gap relative to 2021 ---------------------
use "$panel_in", clear
bysort market_id: egen gap_2021 = max(cond(year == 2021, affordability_gap, .))
gen gap_relative_2021 = affordability_gap - gap_2021
label var gap_relative_2021 "Affordability gap relative to 2021"

preserve
    collapse (mean) mean_gap_rel2021 = gap_relative_2021, by(year exposure_tercile)
    twoway ///
        (line mean_gap_rel2021 year if exposure_tercile == 1, sort) ///
        (line mean_gap_rel2021 year if exposure_tercile == 2, sort) ///
        (line mean_gap_rel2021 year if exposure_tercile == 3, sort), ///
        xline(2022, lpattern(dash)) yline(0, lpattern(dot)) ///
        legend(order(1 "Low pre-exposure" 2 "Middle pre-exposure" 3 "High pre-exposure")) ///
        title("Change in Affordability Gap Relative to 2021") ///
        subtitle("Market-level gap normalized to zero in 2021") ///
        xtitle("Year") ytitle("Average change from 2021") ///
        graphregion(color(white))
    graph export "$output/fig2_gap_relative_2021_by_tercile${fig_suffix}_Tran.png", replace width(2400)
restore


* -------------------------- Fig 3: scatter (long diff) ----------------------
use "$panel_in", clear
capture drop gap_2021
capture drop gap_2023
capture drop post_gap_change
capture drop tag_market
bysort market_id: egen gap_2021 = max(cond(year == 2021, affordability_gap, .))
bysort market_id: egen gap_2023 = max(cond(year == 2023, affordability_gap, .))
gen post_gap_change = gap_2023 - gap_2021
label var post_gap_change "2023 affordability gap minus 2021 gap"

egen tag_market = tag(market_id)

* Diagnostics
count if tag_market == 1
count if tag_market == 1 & !missing(pre_exposure_z, post_gap_change)
summ pre_exposure_z post_gap_change if tag_market == 1, detail

twoway ///
    (scatter post_gap_change pre_exposure_z if tag_market == 1, ///
        mlabel(cma_name) mlabsize(tiny)) ///
    (lfit post_gap_change pre_exposure_z if tag_market == 1), ///
    yline(0, lpattern(dot)) xline(0, lpattern(dot)) ///
    title("Pre-2022 Exposure and Affordability Deterioration") ///
    subtitle("Change from 2021 to 2023, actual T1FF income") ///
    xtitle("Standardized pre-2022 price-to-income exposure") ///
    ytitle("Change in affordability gap, 2023 minus 2021") ///
    legend(order(1 "CMA/proxy market" 2 "Linear fit")) ///
    graphregion(color(white))
graph export "$output/fig3_exposure_vs_gap_change_2021_2023${fig_suffix}_Tran.png", replace width(2400)

* Long-difference regression (matches 2023 event-study coefficient)
reg post_gap_change pre_exposure_z if tag_market == 1, robust
drop tag_market


* -------------------------- Fig 4: event-study gradient --------------------
use "$panel_in", clear

tempfile betas
tempname handle
postfile `handle' year beta se using `betas', replace

levelsof year, local(years)
foreach y of local years {
    quietly reg affordability_gap pre_exposure_z if year == `y', robust
    post `handle' (`y') (_b[pre_exposure_z]) (_se[pre_exposure_z])
}
postclose `handle'

use `betas', clear
gen ci_low  = beta - 1.96 * se
gen ci_high = beta + 1.96 * se
summ beta if year == 2021, meanonly
gen beta_relative_2021    = beta    - r(mean)
gen ci_low_relative_2021  = ci_low  - r(mean)
gen ci_high_relative_2021 = ci_high - r(mean)

twoway ///
    (rcap ci_low_relative_2021 ci_high_relative_2021 year) ///
    (connected beta_relative_2021 year), ///
    xline(2022, lpattern(dash)) yline(0, lpattern(dot)) ///
    title("Event-Study-Style Exposure Gradient") ///
    subtitle("Cross-sectional exposure slope, normalized to 2021") ///
    xtitle("Year") ytitle("Exposure coefficient relative to 2021") ///
    legend(order(1 "95% CI" 2 "Exposure gradient")) ///
    graphregion(color(white))
graph export "$output/fig4_event_style_exposure_gradient${fig_suffix}_Tran.png", replace width(2400)


* -------------------------- Log gap over time (PDF) -------------------------
use "$panel_in", clear
capture drop log_gap_check
gen log_gap_check = ln(benchmark_price) - ln(max_qualified_price)
summ affordability_gap log_gap_check

preserve
    collapse (mean) mean_log_gap = affordability_gap, by(year exposure_tercile)
    twoway ///
        (line mean_log_gap year if exposure_tercile == 1, sort) ///
        (line mean_log_gap year if exposure_tercile == 2, sort) ///
        (line mean_log_gap year if exposure_tercile == 3, sort), ///
        xline(2022, lpattern(dash)) yline(0, lpattern(dot)) ///
        legend(order(1 "Low pre-exposure" 2 "Middle pre-exposure" 3 "High pre-exposure")) ///
        title("Log Affordability Gap Over Time") ///
        subtitle("ln(benchmark price) - ln(max qualified price), actual T1FF income") ///
        xtitle("Year") ytitle("Average log affordability gap") ///
        graphregion(color(white))
    graph export "$output/Graph_Log_affordability_gap_over_time${fig_suffix}_Tran.pdf", replace
restore


* -------------------------- Qualifying-rate path ---------------------------
use "$clean/mortgage_rate_annual_clean_Tran.dta", clear
keep if inrange(year, 2016, 2023)

twoway ///
    (connected contract_rate_5yr year, lpattern(dash)) ///
    (connected qual_rate year), ///
    xline(2022, lpattern(dash)) ///
    legend(order(1 "BoC 5-yr posted rate" 2 "OSFI qualifying rate")) ///
    title("Contract vs. Qualifying Mortgage Rate") ///
    subtitle("Annual averages, 2016-2023") ///
    xtitle("Year") ytitle("Percent") ///
    graphregion(color(white))
graph export "$output/qual_rate_path${fig_suffix}.png", replace width(2400)


* -------------------------- End of figures/descriptives --------------------
* The formatted summary-statistics TABLE (paper-ready) is written once, by
* 11_paper_outputs.do via outreg2 (tab1_summary_stats_Tran.doc). This file
* produces only the FIGURES plus the quick-look summary_stats xlsx above, to
* keep the output folder free of duplicate table files.
display as text ""
display as text "Figures written. Summary-stats TABLE is produced by 11_paper_outputs.do."
display as text ""
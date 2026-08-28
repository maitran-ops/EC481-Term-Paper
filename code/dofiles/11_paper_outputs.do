*==============================================================================
* 11_paper_outputs.do  --  Raw Stata output tables via outreg2
*------------------------------------------------------------------------------
* PURPOSE
*   Write the regression results directly from the estimation commands using
*   outreg2 -- NOT hand-built, NOT post-processed. Each table is outreg2's own
*   formatted output, produced by the estimation command that generated it.
*
* REQUIRES
*   ssc install outreg2
*
* RUN ORDER
*   Run this AFTER 09_regressions.do and 10_composite_robustness.do, since
*   Table 3 reuses the composite HPI files 10_composite_robustness.do caches.
*
* OUTPUT (all written directly by outreg2; .doc opens natively in Word):
*   $output/tab1_summary_stats_Tran.doc
*   $output/tab2_main_results_Tran.doc   (+ tab2_main_results_Tran.tex)
*   $output/tab3_composite_robustness_Tran.doc
*==============================================================================

capture which outreg2
if _rc {
    display as error "outreg2 not installed. Run:  ssc install outreg2"
    display as error "Skipping 11_paper_outputs.do -- install outreg2 and re-run this file."
    exit 0
}

use "$clean/core_affordability_panel_expanded_Tran.dta", clear
xtset market_id year

* ---------------------------------------------------------------------------
* Table 1: summary statistics -- outreg2's sum(log) option writes directly
* from -summarize-, nothing retyped.
* ---------------------------------------------------------------------------
capture erase "$output/tab1_summary_stats_Tran.doc"
outreg2 using "$output/tab1_summary_stats_Tran.doc", replace word ///
    sum(log) title("Table 1. Summary statistics -- 36 Canadian CMAs, 2016-2023") ///
    keep(benchmark_price median_income qual_rate max_qualified_price ///
         affordability_gap price_income_ratio pre_exposure_z)

* ---------------------------------------------------------------------------
* Table 2: main results + leave-out robustness. Each xtreg is estimated, then
* outreg2 appends that model as a new column -- output comes straight from
* e(b)/e(V) of the command just run.
* ---------------------------------------------------------------------------
capture erase "$output/tab2_main_results_Tran.doc"

xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
    fe vce(cluster cluster_id)
outreg2 using "$output/tab2_main_results_Tran.doc", replace word ///
    title("Table 2. Continuous-treatment DiD estimates (36 CMAs)") ///
    ctitle("Main") keep(c.qual_rate#c.pre_exposure_z) ///
    addstat(Within R-sq, e(r2_w)) ///
    addtext(Market FE, YES, Year FE, YES, Sample, All 36 CMAs) ///
    label bdec(4) sdec(4)

xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year ///
    if cma_name != "Vancouver", fe vce(cluster cluster_id)
outreg2 using "$output/tab2_main_results_Tran.doc", append word ///
    ctitle("No Vancouver") keep(c.qual_rate#c.pre_exposure_z) ///
    addstat(Within R-sq, e(r2_w)) ///
    addtext(Market FE, YES, Year FE, YES, Sample, Drop Vancouver) ///
    label bdec(4) sdec(4)

xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year ///
    if !inlist(cma_name, "Toronto", "Vancouver"), fe vce(cluster cluster_id)
outreg2 using "$output/tab2_main_results_Tran.doc", append word ///
    ctitle("No Tor+Van") keep(c.qual_rate#c.pre_exposure_z) ///
    addstat(Within R-sq, e(r2_w)) ///
    addtext(Market FE, YES, Year FE, YES, Sample, Drop Toronto+Vancouver) ///
    label bdec(4) sdec(4)

xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year ///
    if province != "BC", fe vce(cluster cluster_id)
outreg2 using "$output/tab2_main_results_Tran.doc", append word ///
    ctitle("No BC") keep(c.qual_rate#c.pre_exposure_z) ///
    addstat(Within R-sq, e(r2_w)) ///
    addtext(Market FE, YES, Year FE, YES, Sample, Drop all BC) ///
    label bdec(4) sdec(4)

capture drop bc_post
gen byte bc_post = (province == "BC") & (year >= 2022)
label variable bc_post "BC x post-2022"
xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year bc_post, ///
    fe vce(cluster cluster_id)
outreg2 using "$output/tab2_main_results_Tran.doc", append word ///
    ctitle("BC x Post ctrl") keep(c.qual_rate#c.pre_exposure_z bc_post) ///
    addstat(Within R-sq, e(r2_w)) ///
    addtext(Market FE, YES, Year FE, YES, Sample, All 36 CMAs) ///
    label bdec(4) sdec(4)

* Same main column as a .tex fragment for Overleaf
xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
    fe vce(cluster cluster_id)
outreg2 using "$output/tab2_main_results_Tran.tex", replace tex(fragment) ///
    ctitle("Main") keep(c.qual_rate#c.pre_exposure_z) ///
    addstat(Within R-sq, e(r2_w)) label bdec(4) sdec(4)

* ---------------------------------------------------------------------------
* Table 3: composite-HPI robustness (single board vs 3 weight schemes).
* Reuses the composite files 10_composite_robustness.do writes, so the three
* extra columns are estimated on the SAME composite series checked there --
* nothing rebuilt or retyped in this file.
* ---------------------------------------------------------------------------
capture erase "$output/tab3_composite_robustness_Tran.doc"

xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
    fe vce(cluster cluster_id)
outreg2 using "$output/tab3_composite_robustness_Tran.doc", replace word ///
    title("Table 3. Robustness to HPI construction") ///
    ctitle("Single board (primary)") ///
    keep(c.qual_rate#c.pre_exposure_z) label bdec(4) sdec(4)

tempfile base_panel
save `base_panel', replace

foreach sch in approx equal pop_share {
    capture confirm file "$clean/hpi_composite_`sch'_Tran.dta"
    if _rc {
        display as text "Composite scheme `sch' not cached -- run 10_composite_robustness.do first. Skipping this column."
        continue
    }
    use `base_panel', clear
    merge m:1 cma_name year using "$clean/hpi_composite_`sch'_Tran.dta"
    replace benchmark_price = benchmark_price_composite if !missing(benchmark_price_composite)
    drop _merge benchmark_price_composite
    replace affordability_gap = ln(benchmark_price) - ln(max_qualified_price)
    xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
        fe vce(cluster cluster_id)
    outreg2 using "$output/tab3_composite_robustness_Tran.doc", append word ///
        ctitle("Composite, `sch'") ///
        keep(c.qual_rate#c.pre_exposure_z) label bdec(4) sdec(4)
}
use `base_panel', clear

display as text ""
display as text "=========================================================="
display as text " outreg2 tables written to $output :"
display as text "   tab1_summary_stats_Tran.doc"
display as text "   tab2_main_results_Tran.doc  (+ tab2_main_results_Tran.tex)"
display as text "   tab3_composite_robustness_Tran.doc"
display as text " Raw outreg2 output -- open directly in Word, no editing needed."
display as text " Figures are separate PNGs from 08_figures_tables.do; insert"
display as text " them into the paper alongside these tables."
display as text "=========================================================="

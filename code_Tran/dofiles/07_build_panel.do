*==============================================================================
* 07_build_panel.do  --  Assemble analysis panel
*------------------------------------------------------------------------------
* Steps
*   (a) Merge HPI-CMA baseline with T1FF income.
*   (b) If composite HPI exists (from 04_composite_hpi.do), overwrite the
*       benchmark price for multi-board CMAs.
*   (c) Merge annual qualifying rate.
*   (d) Compute max qualified price and log affordability gap.
*   (e) Build pre-2022 exposure and exposure terciles.
*
* Input : $clean/hpi_cma_clean_Tran.dta          (31-market baseline)
*        [$clean/hpi_cma_expanded_Tran.dta]       (36-CMA, if 04b ran)
*         $clean/income_cma_clean_Tran.dta
*         $clean/mortgage_rate_annual_clean_Tran.dta
*        [$clean/hpi_composite_by_cma_Tran.dta]  -- optional
* Output: $clean/core_affordability_panel_Tran.dta          (baseline)
*        [$clean/core_affordability_panel_expanded_Tran.dta] (expanded)
*
* SAMPLE TOGGLE
*   global sample_mode controls which HPI panel is built. Set it before
*   calling this file (00_master.do sets it). Default = baseline.
*     "baseline" -> hpi_cma_clean_Tran.dta      -> core_affordability_panel_Tran.dta
*     "expanded" -> hpi_cma_expanded_Tran.dta   -> core_affordability_panel_expanded_Tran.dta
*==============================================================================

if "$sample_mode" == "" global sample_mode "baseline"

if "$sample_mode" == "expanded" {
    capture confirm file "$clean/hpi_cma_expanded_Tran.dta"
    if _rc {
        display as error "Expanded HPI not found; run 04b_expand_sample.do first. Falling back to baseline."
        global sample_mode "baseline"
    }
}

if "$sample_mode" == "expanded" {
    global hpi_in  "$clean/hpi_cma_expanded_Tran.dta"
    global panel_out "$clean/core_affordability_panel_expanded_Tran.dta"
}
else {
    global hpi_in  "$clean/hpi_cma_clean_Tran.dta"
    global panel_out "$clean/core_affordability_panel_Tran.dta"
}
display as text "Building panel in sample_mode = $sample_mode"

* ---------- (a) HPI ---------------------------------------------------------
use "$hpi_in", clear

* Ensure a cluster_id exists (baseline file may not carry one)
capture confirm variable cluster_id
if _rc {
    egen cluster_id = group(cma_name), label
}
capture confirm variable match_quality
if _rc gen match_quality = "baseline"

* CMA key
capture drop cma_key
gen cma_key = cma_name
replace cma_key = ustrlower(cma_key)
replace cma_key = subinstr(cma_key, "_", " ", .)
replace cma_key = subinstr(cma_key, "-", " ", .)
replace cma_key = subinstr(cma_key, "–", " ", .)
replace cma_key = subinstr(cma_key, "/", " ", .)
replace cma_key = subinstr(cma_key, ".", " ", .)
replace cma_key = subinstr(cma_key, "'", " ", .)
replace cma_key = subinstr(cma_key, "é", "e", .)
replace cma_key = subinstr(cma_key, "è", "e", .)
replace cma_key = subinstr(cma_key, "ê", "e", .)
replace cma_key = subinstr(cma_key, "ë", "e", .)
replace cma_key = subinstr(cma_key, "à", "a", .)
replace cma_key = subinstr(cma_key, "â", "a", .)
replace cma_key = subinstr(cma_key, "ô", "o", .)
replace cma_key = subinstr(cma_key, "î", "i", .)
replace cma_key = subinstr(cma_key, "ï", "i", .)
replace cma_key = subinstr(cma_key, "ç", "c", .)
replace cma_key = strtrim(itrim(cma_key))
replace cma_key = "greater sudbury" if cma_key == "greater sudbury grand sudbury"

keep if inrange(year, 2016, 2023)

* ---------- (b) Overwrite HPI with composite where available ---------------
* Composite HPI is OPT-IN, not automatic. Verified against the raw data
* (household-weighted composite vs. single-board): beta moves only from
* -0.0165 to -0.0154 (both insignificant) -- a small, stable difference.
* Because exact household weights require CREA boundary files that were
* never obtained, SINGLE-BOARD is the primary spec (zero unverifiable
* weighting assumptions, largest |beta|, most conservative). The composite,
* under three weight schemes, is reported as a robustness check in
* 10_composite_robustness.do, not baked into the main panel.
if "$use_composite_primary" == "1" {
    capture confirm file "$clean/hpi_composite_by_cma_Tran.dta"
    if !_rc {
        capture confirm variable ln_benchmark_price
        if _rc gen ln_benchmark_price = ln(benchmark_price)
        gen double _bp_pre = benchmark_price
        merge m:1 cma_name year using "$clean/hpi_composite_by_cma_Tran.dta"
        keep if inlist(_merge, 1, 3)                       // keep base HPI where no composite
        replace benchmark_price = benchmark_price_composite if !missing(benchmark_price_composite)
        * Report which CMAs were actually overwritten and by how much (2023).
        gen double _delta = 100*(benchmark_price/_bp_pre - 1)
        display as text "Composite HPI applied to these CMAs (2023 % change vs single board):"
        list cma_name year _delta if !missing(benchmark_price_composite) & year==2023, ///
            sepby(cma_name) noobs
        drop _merge benchmark_price_composite _bp_pre _delta
        replace ln_benchmark_price = ln(benchmark_price)
        display as text "Composite HPI merged for multi-board CMAs (use_composite_primary=1)."
    }
    else {
        display as text "use_composite_primary=1 but composite file not found; using single board."
    }
}
else {
    display as text "Single board per CMA (primary spec). Composite HPI is a"
    display as text "robustness check only -- see 10_composite_robustness.do."
}

* ---------- (c) Merge income -----------------------------------------------
preserve
    use "$clean/income_cma_clean_Tran.dta", clear
    isid cma_key year
restore
merge m:1 cma_key year using "$clean/income_cma_clean_Tran.dta"
* Diagnostic: unmatched HPI-side rows (income missing for that market-year)
capture confirm variable crea_market
if !_rc {
    list crea_market cma_name province year cma_key if _merge == 1, sepby(cma_name)
}
else {
    list cma_name province year cma_key if _merge == 1, sepby(cma_name)
}
list cma_name_income year cma_key if _merge == 2, sepby(cma_name_income)
keep if _merge == 3
drop _merge

* ---------- (d) Merge annual rates ----------------------------------------
merge m:1 year using "$clean/mortgage_rate_annual_clean_Tran.dta"
list year if _merge != 3
keep if _merge == 3
drop _merge

* ---------- (d2) Merge supply/demand controls (mechanism check only) -------
* ln_pop, ln_starts, unemp_rate are used ONLY in the exploratory mechanism
* regressions in 09_regressions.do, never the primary spec. Merge is m:1 on
* cma_key x year. Housing starts is missing for six 2021-Census-reclassified
* CMAs before 2023 (documented in 06b_clean_controls.do); those cells stay
* missing and are dropped by the FE estimator in the starts spec alone.
capture confirm file "$clean/controls_cma_clean_Tran.dta"
if !_rc {
    merge m:1 cma_key year using "$clean/controls_cma_clean_Tran.dta"
    * _merge==1: panel row with no control match (should not happen for pop/unemp)
    * _merge==2: control row not in panel (other CMAs) -> drop
    list cma_name year if _merge == 1, sepby(cma_name)
    drop if _merge == 2
    drop _merge
    display as text "Controls merged (ln_pop, ln_starts, unemp_rate)."
    count if !missing(ln_starts)
    display as text "  Non-missing housing-starts CMA-years: `r(N)' of `=_N'."
}
else {
    display as text "Controls file not found; mechanism vars will be skipped in 09."
}

summ benchmark_price median_income contract_rate_5yr qual_rate
save "$panel_out", replace


* ---------- (e) Construct affordability gap --------------------------------
use "$panel_out", clear

* Payment cap: 39 % GDS (CMHC)
gen max_monthly_payment = 0.39 * median_income / 12

* Semi-annual compounding -> monthly rate
gen qual_rate_monthly = (1 + qual_rate/200)^(1/6) - 1

* 25-year amortization
gen amort_months = 300
gen max_mortgage = max_monthly_payment * ///
    (1 - (1 + qual_rate_monthly)^(-amort_months)) / qual_rate_monthly

* 20 % down payment -> maximum qualified price
gen max_qualified_price = max_mortgage / 0.80

gen affordability_gap = ln(benchmark_price) - ln(max_qualified_price)
gen affordability_gap_pct = exp(affordability_gap) - 1
gen price_income_ratio = benchmark_price / median_income

label var max_monthly_payment "Max monthly payment, 39% of income"
label var qual_rate_monthly   "Monthly mortgage qualifying rate"
label var max_mortgage        "Max mortgage principal"
label var max_qualified_price "Mortgage-qualified maximum home price"
label var affordability_gap     "ln(benchmark) - ln(max qualified price)"
label var affordability_gap_pct "Affordability gap, percent form"
label var price_income_ratio    "Benchmark price-to-income ratio"

summ benchmark_price median_income contract_rate_5yr qual_rate ///
     max_qualified_price affordability_gap affordability_gap_pct ///
     price_income_ratio, detail

* Sanity: no implausible affordability gaps (|log gap| > 2 would be ~7x mispricing).
capture assert abs(affordability_gap) < 2 if !missing(affordability_gap)
if _rc {
    display as error "*** Implausible affordability_gap (|log gap| > 2). Inspect below. ***"
    list cma_name year benchmark_price median_income affordability_gap ///
        if abs(affordability_gap) >= 2
    exit 459
}

save "$panel_out", replace


* ---------- (f) Pre-2022 exposure and terciles -----------------------------
use "$panel_out", clear

* Raw exposure: average 2016-2021 P/I
egen pre_exposure_raw = mean(cond(inrange(year, 2016, 2021), ///
    price_income_ratio, .)), by(market_id)
label var pre_exposure_raw "Avg 2016-2021 benchmark-price-to-income ratio"

* Standardize across markets in the active sample (use one-per-market tag)
egen tag_market = tag(market_id)
summ pre_exposure_raw if tag_market == 1
local m = r(mean)
local s = r(sd)
gen pre_exposure_z = (pre_exposure_raw - `m') / `s'
label var pre_exposure_z "Standardized pre-2022 price-to-income exposure"

* Terciles
xtile exposure_tercile_temp = pre_exposure_raw if tag_market == 1, nq(3)
bysort market_id: egen exposure_tercile = max(exposure_tercile_temp)
drop exposure_tercile_temp
label define expterc 1 "Low pre-exposure" 2 "Middle pre-exposure" 3 "High pre-exposure", replace
label values exposure_tercile expterc

tab exposure_tercile if tag_market == 1
summ pre_exposure_raw pre_exposure_z if tag_market == 1, detail
list cma_name province pre_exposure_raw pre_exposure_z exposure_tercile ///
    if tag_market == 1, sepby(exposure_tercile)
drop tag_market

xtset market_id year
save "$panel_out", replace

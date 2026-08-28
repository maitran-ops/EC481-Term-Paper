*==============================================================================
* 10_composite_robustness.do  --  Composite HPI robustness (3 weight schemes)
*------------------------------------------------------------------------------
* CONTEXT
*   Four expanded-sample CMAs (Toronto, Vancouver, Kitchener-Cambridge-Waterloo,
*   Barrie) are served by more than one CREA board. The primary specification
*   (07_build_panel.do, use_composite_primary NOT set to 1) uses a single core
*   board per CMA -- the most defensible choice because it makes zero
*   unverifiable weighting assumptions (CREA never released board boundary
*   files, so exact household shares cannot be computed).
*
*   This file checks that decision does not drive the result: it re-estimates
*   beta with a household-weighted composite HPI for those four CMAs under
*   THREE weighting schemes, so the weight-uncertainty becomes a demonstrated
*   non-issue rather than a hidden assumption.
*
*     approx     : public board-coverage pages + 2021 census dwelling counts
*                  (household_weights.xlsx -- the original approximation)
*     equal      : 1/n across each CMA's constituent boards
*     pop_share  : population-share approximation from 2021 census subdivision
*                  totals (coarser than approx, independent construction)
*
* Input : $clean/hpi_annual_clean_Tran.dta
*         $clean/core_affordability_panel_expanded_Tran.dta  (for the merge keys)
* Output: prints beta/SE/p for single-board vs. all three composite schemes.
*==============================================================================

capture confirm file "$clean/core_affordability_panel_expanded_Tran.dta"
if _rc {
    display as error "Expanded panel not found; run 07_build_panel.do (expanded) first."
    exit 601
}

* -------------------------- Weight scheme definitions -----------------------
* Each scheme: cma_name  crea_market  weight  scheme
tempfile allweights
clear
input str40 cma_name str30 crea_market double weight str12 scheme
"Toronto"                          "GREATER_TORONTO"     0.78  "approx"
"Toronto"                          "MISSISSAUGA"         0.14  "approx"
"Toronto"                          "OAKVILLE_MILTON"     0.08  "approx"
"Vancouver"                        "GREATER_VANCOUVER"   0.88  "approx"
"Vancouver"                        "FRASER_VALLEY"       0.12  "approx"
"Kitchener - Cambridge - Waterloo" "KITCHENER_WATERLOO"  0.72  "approx"
"Kitchener - Cambridge - Waterloo" "CAMBRIDGE"           0.28  "approx"
"Barrie"                           "BARRIE_AND_DISTRICT" 0.82  "approx"
"Barrie"                           "SIMCOE_AND_DISTRICT" 0.18  "approx"
"Toronto"                          "GREATER_TORONTO"     0.3333 "equal"
"Toronto"                          "MISSISSAUGA"         0.3333 "equal"
"Toronto"                          "OAKVILLE_MILTON"     0.3334 "equal"
"Vancouver"                        "GREATER_VANCOUVER"   0.50  "equal"
"Vancouver"                        "FRASER_VALLEY"       0.50  "equal"
"Kitchener - Cambridge - Waterloo" "KITCHENER_WATERLOO"  0.50  "equal"
"Kitchener - Cambridge - Waterloo" "CAMBRIDGE"           0.50  "equal"
"Barrie"                           "BARRIE_AND_DISTRICT" 0.50  "equal"
"Barrie"                           "SIMCOE_AND_DISTRICT" 0.50  "equal"
"Toronto"                          "GREATER_TORONTO"     0.80  "pop_share"
"Toronto"                          "MISSISSAUGA"         0.13  "pop_share"
"Toronto"                          "OAKVILLE_MILTON"     0.07  "pop_share"
"Vancouver"                        "GREATER_VANCOUVER"   0.85  "pop_share"
"Vancouver"                        "FRASER_VALLEY"       0.15  "pop_share"
"Kitchener - Cambridge - Waterloo" "KITCHENER_WATERLOO"  0.75  "pop_share"
"Kitchener - Cambridge - Waterloo" "CAMBRIDGE"           0.25  "pop_share"
"Barrie"                           "BARRIE_AND_DISTRICT" 0.75  "pop_share"
"Barrie"                           "SIMCOE_AND_DISTRICT" 0.25  "pop_share"
end
save `allweights', replace

* Results collector
tempname rh
tempfile results
postfile `rh' str20 scheme double beta se pval long nobs long nclus using `results', replace

* -------------------------- Single-board baseline (for comparison) ---------
use "$clean/core_affordability_panel_expanded_Tran.dta", clear
xtset market_id year
quietly xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
    fe vce(cluster cluster_id)
post `rh' ("single_board") (_b[c.qual_rate#c.pre_exposure_z]) ///
    (_se[c.qual_rate#c.pre_exposure_z]) (2*ttail(e(df_r), abs(_b[c.qual_rate#c.pre_exposure_z]/_se[c.qual_rate#c.pre_exposure_z]))) ///
    (e(N)) (e(N_clust))

* -------------------------- Composite schemes -------------------------------
foreach sch in approx equal pop_share {

    * Build the composite HPI for this scheme
    preserve
        use `allweights', clear
        keep if scheme == "`sch'"
        drop scheme
        tempfile wsch
        save `wsch', replace
    restore

    preserve
        use "$clean/hpi_annual_clean_Tran.dta", clear
        replace crea_market = strtrim(itrim(crea_market))
        merge m:1 crea_market using `wsch'
        * _merge==2 => a weight row whose board has no HPI series (shouldn't happen
        * for these 9 boards, but check defensively)
        capture assert _merge != 2
        if _rc {
            display as error "Weight scheme `sch': a board in the weight file has no HPI series."
            list crea_market if _merge == 2
        }
        keep if _merge == 3
        drop _merge
        gen weighted_price = weight * benchmark_price
        collapse (sum) benchmark_price_composite = weighted_price, by(cma_name year)
        tempfile compsch
        save `compsch', replace
        * Also cache persistently so 11_paper_outputs.do (outreg2 table 3) can
        * reuse this exact composite series without rebuilding it.
        save "$clean/hpi_composite_`sch'_Tran.dta", replace
    restore

    * Merge composite onto the single-board expanded panel, overwrite the 4 CMAs
    use "$clean/core_affordability_panel_expanded_Tran.dta", clear
    merge m:1 cma_name year using `compsch'
    replace benchmark_price = benchmark_price_composite if !missing(benchmark_price_composite)
    drop _merge benchmark_price_composite

    * Recompute the affordability gap with the composite-adjusted price
    replace affordability_gap = ln(benchmark_price) - ln(max_qualified_price)

    * Re-standardize pre-2022 exposure under the composite (small mechanical
    * change for the 4 affected CMAs' pre-period P/I ratio)
    replace price_income_ratio = benchmark_price / median_income
    capture drop pre_exposure_raw
    capture drop pre_exposure_z
    capture drop tag_market
    egen pre_exposure_raw = mean(cond(inrange(year,2016,2021), price_income_ratio, .)), by(market_id)
    egen tag_market = tag(market_id)
    quietly summ pre_exposure_raw if tag_market == 1
    gen pre_exposure_z = (pre_exposure_raw - r(mean)) / r(sd)
    drop tag_market

    xtset market_id year
    quietly xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
        fe vce(cluster cluster_id)
    post `rh' ("`sch'") (_b[c.qual_rate#c.pre_exposure_z]) ///
        (_se[c.qual_rate#c.pre_exposure_z]) (2*ttail(e(df_r), abs(_b[c.qual_rate#c.pre_exposure_z]/_se[c.qual_rate#c.pre_exposure_z]))) ///
        (e(N)) (e(N_clust))
}

postclose `rh'

* -------------------------- Report ------------------------------------------
use `results', clear
display as text ""
display as text "=========================================================="
display as text " Table 2: robustness of beta to HPI construction (36-CMA)"
display as text "=========================================================="
list scheme beta se pval nobs nclus, noobs sep(0)

capture which esttab
if _rc == 0 {
    export excel using "$output/table2_composite_robustness_Tran.xlsx", ///
        firstrow(variables) replace
    display as text "Also written to $output/table2_composite_robustness_Tran.xlsx"
}

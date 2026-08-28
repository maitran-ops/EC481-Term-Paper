*==============================================================================
* 09_regressions.do  --  Baseline DiD, event study, long diff, wild bootstrap,
*                        mechanisms sequence
*------------------------------------------------------------------------------
* Input : $clean/core_affordability_panel_Tran.dta
* Output: stored estimates (main, eventstudy, mech_*)
*         boottest results printed to log
*         optional esttab table -> $output/reg_table_Tran.tex
*==============================================================================

use "$clean/core_affordability_panel_Tran.dta", clear
xtset market_id year

* -------------------------- (1) Baseline continuous-treatment DiD ----------
* QualRate is absorbed by year FE, PreExposure by market FE; the interaction
* is what is identified. SEs clustered by market (level of treatment
* assignment, per DR feedback).

xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
    fe vce(cluster market_id)
estimates store main


* -------------------------- (2) Event study --------------------------------
* 2021 = base (last pre-tightening year). Pre-2022 interactions near zero
* support parallel trends; 2022-2023 are the differential response.

xtreg affordability_gap ib2021.year##c.pre_exposure_z, ///
    fe vce(cluster market_id)
estimates store eventstudy

* Joint pre-trends test: the 2016-2020 exposure INTERACTIONS are jointly zero.
* Use testparm with the interaction-only factor syntax. Both plain "test
* 2016.year#c..." and "test (_b[2016.year#c...]=0)" wrongly pull in the large
* year MAIN effects, producing a spurious F ~ 28. testparm with the
* "i(2016/2020).year#c.pre_exposure_z" pattern tests ONLY the interactions.
testparm i(2016/2020).year#c.pre_exposure_z


* -------------------------- (3) Long-difference regression -----------------
preserve
    capture drop gap_2021
    capture drop gap_2023
    capture drop post_gap_change
    capture drop tag_market
    bysort market_id: egen gap_2021 = max(cond(year == 2021, affordability_gap, .))
    bysort market_id: egen gap_2023 = max(cond(year == 2023, affordability_gap, .))
    gen post_gap_change = gap_2023 - gap_2021
    egen tag_market = tag(market_id)
    reg post_gap_change pre_exposure_z if tag_market == 1, robust
    estimates store longdiff
restore


* -------------------------- (4) Wild cluster bootstrap ---------------------
* With only 31 clusters, conventional t-based cluster-robust p-values may
* over-reject (Cameron, Gelbach & Miller 2008; MacKinnon & Webb 2018).
* Bootstrap-t confidence interval with Rademacher weights, B = 9999.
* Requires:  ssc install boottest

capture which boottest
if _rc == 0 {
    estimates restore main
    boottest c.qual_rate#c.pre_exposure_z, reps(9999) cluster(market_id) ///
        boottype(wild) weighttype(rademacher) seed(20260708)
}
else {
    display as text ""
    display as text "-------------------------------------------------------"
    display as text "  boottest not installed. Install with:"
    display as text "     ssc install boottest, replace"
    display as text "-------------------------------------------------------"
}


* -------------------------- (5) Mechanisms sequence ------------------------
* EXPLORATORY only, reported as a robustness/mechanism check, NOT as the
* primary spec. Population, labour, and housing starts are plausibly
* post-treatment OUTCOMES of the qualifying rate (bad-controls concern), so
* adding them can absorb part of the very effect beta measures. We therefore
* report the baseline beta, then beta with each control added one at a time,
* and read the CHANGE descriptively -- never as a cleaner causal estimate.
*
* Housing starts (ln_starts) is available for only 30 of 36 CMAs before 2023
* (six CMAs reclassified under 2021-Census geography; see 06b_clean_controls),
* so its column runs on a reduced sample. We print that sample size explicitly
* so the reduced-N is transparent and never mistaken for the full panel.
*
* Fires only if the controls were merged into core_affordability_panel.

* Run the mechanism check on the EXPANDED 36-CMA panel (the paper's primary
* sample), which carries the merged controls. Load it explicitly so this block
* is correct regardless of what is in memory. Wrapped in preserve/restore so
* the baseline panel in memory is untouched for the sections that follow.
preserve
capture confirm file "$clean/core_affordability_panel_expanded_Tran.dta"
if !_rc {
    use "$clean/core_affordability_panel_expanded_Tran.dta", clear
    xtset market_id year
}

* Baseline beta on the FULL sample, for side-by-side comparison.
xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
    fe vce(cluster market_id)
estimates store mech_base
display as text "Mechanism baseline: beta = " %7.4f _b[c.qual_rate#c.pre_exposure_z] ///
    "  (N = " e(N) ", groups = " e(N_g) ")"

foreach v in ln_pop unemp_rate ln_starts {
    capture confirm variable `v'
    if !_rc {
        xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year `v', ///
            fe vce(cluster market_id)
        estimates store mech_`v'
        display as text "Add `v': beta = " %7.4f _b[c.qual_rate#c.pre_exposure_z] ///
            "  (N = " e(N) ", groups = " e(N_g) ")"
        * For the reduced-sample control (starts), also report the baseline
        * beta ON THE SAME reduced sample, so the comparison is like-for-like
        * rather than confounded by the change in sample.
        if "`v'" == "ln_starts" {
            xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year ///
                if !missing(ln_starts), fe vce(cluster market_id)
            estimates store mech_starts_basesample
            display as text "  (same 30-CMA sample, NO control): beta = " ///
                %7.4f _b[c.qual_rate#c.pre_exposure_z] "  (N = " e(N) ")"
        }
    }
    else {
        display as text "Mechanism variable `v' not merged; skipped."
    }
}

* Compact table of the mechanism sequence for the log / paper appendix.
capture which esttab
if _rc == 0 {
    esttab mech_base mech_ln_pop mech_unemp_rate mech_starts_basesample mech_ln_starts, ///
        keep(c.qual_rate#c.pre_exposure_z ln_pop unemp_rate ln_starts) ///
        b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
        mtitles("Base(36)" "+lnPop(36)" "+Unemp(36)" "Base(30)" "+lnStarts(30)") ///
        title("Mechanism/robustness controls -- exploratory, not primary")
}
restore

* -------------------------- (6) Robustness: drop Vancouver -----------------
* Vancouver is the exposure outlier (z = 3.26). Re-estimate without it to
* see whether the long-difference slope is leverage-driven.
preserve
    drop if cma_name == "Vancouver"
    xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
        fe vce(cluster market_id)
    estimates store main_novan
restore


* -------------------------- (7) Expanded 36-CMA sample ------------------
* Reads the expanded panel built by 04b_expand_sample.do + 07 (expanded mode).
* Markets sharing a CREA board (Kelowna & Kamloops on INTERIOR_BC) share a
* cluster, so cluster on cluster_id, NOT market_id. This is the honest
* inference level once shared-HPI proxies enter the sample.
capture confirm file "$clean/core_affordability_panel_expanded_Tran.dta"
if _rc == 0 {
    preserve
        use "$clean/core_affordability_panel_expanded_Tran.dta", clear
        xtset market_id year

        * Expanded baseline, clustered by board
        xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
            fe vce(cluster cluster_id)
        estimates store main_expanded

        * Expanded, dropping Vancouver (leverage check on the wider sample)
        xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year ///
            if cma_name != "Vancouver", fe vce(cluster cluster_id)
        estimates store main_expanded_novan

        * Expanded, dropping BOTH Toronto and Vancouver.
        * Peer/prof point: the two largest markets dominate the high-exposure end
        * and are driven by forces (foreign capital, student/investor demand) the
        * model can't isolate. If the gradient is entirely those two, beta -> ~0.
        xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year ///
            if !inlist(cma_name, "Toronto", "Vancouver"), fe vce(cluster cluster_id)
        estimates store main_expanded_notorvan

        * Expanded, dropping ALL British Columbia markets.
        * Peer/prof point: BC's foreign-buyer tax, speculation/vacancy tax, and the
        * federal foreign-buyer ban are rate-INDEPENDENT policy shocks concentrated
        * in BC. Excluding BC shows whether the result survives without them.
        xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year ///
            if province != "BC", fe vce(cluster cluster_id)
        estimates store main_expanded_nobc

        * Parsimonious BC-policy control: a single BC x post(2022) dummy, rather
        * than dropping BC markets outright. This directly nets out a BC-specific
        * post-2022 level shift (foreign-buyer tax escalation, speculation/vacancy
        * tax, federal foreign-buyer ban) with ONE extra parameter.
        * NOTE: full province x year FE was tested and rejected -- 4 of 10
        * provinces have only 1 market in this sample (MB, ON/QC, NS, NL), so
        * province x year FE perfectly saturates those markets (zero residual
        * variance), manufacturing spurious precision rather than genuinely
        * controlling for anything. The single BC x post dummy avoids this.
        capture drop bc_post
        gen byte bc_post = (province == "BC") & (year >= 2022)
        xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year bc_post, ///
            fe vce(cluster cluster_id)
        estimates store main_expanded_bcpost

        * Count markets and clusters actually estimated
        egen tag_m = tag(market_id)
        egen tag_c = tag(cluster_id)
        count if tag_m == 1
        display as text "Expanded markets estimated:  " r(N)
        count if tag_c == 1
        display as text "Expanded clusters estimated: " r(N)
        drop tag_m tag_c

        * -------------------- Formal leverage diagnostic (DFBETA-style) --------
        * Rather than eyeballing "drop Vancouver", compute the leave-one-market-out
        * beta for EVERY market and report how extreme each market's influence is
        * relative to the full distribution of one-market-out betas.
        * NOTE: uses a tempfile save/reload rather than a second preserve -- Stata
        * allows only ONE active preserve, and we are already inside the outer
        * preserve at the top of this expanded block.
        tempfile _panel_before_loo
        save "`_panel_before_loo'", replace

            quietly xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year, ///
                fe vce(cluster cluster_id)
            local beta_full = _b[c.qual_rate#c.pre_exposure_z]

            levelsof cma_name, local(allmkts)
            tempname lohandle
            tempfile loo
            postfile `lohandle' str40 cma_name_out double beta_excl using `loo', replace
            foreach m of local allmkts {
                quietly xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.year ///
                    if cma_name != "`m'", fe vce(cluster cluster_id)
                post `lohandle' ("`m'") (_b[c.qual_rate#c.pre_exposure_z])
            }
            postclose `lohandle'

            use `loo', clear
            gen dfbeta = beta_excl - `beta_full'
            quietly summ dfbeta
            gen dfbeta_sd = dfbeta / r(sd)
            gen abs_dfbeta = abs(dfbeta)
            gsort -abs_dfbeta
            display as text ""
            display as text "Leave-one-market-out influence, full beta = " %6.4f `beta_full'
            display as text "(top 5 markets by |DFBETA|):"
            list cma_name_out beta_excl dfbeta dfbeta_sd in 1/5, noobs

        * Reload the expanded panel so the region x year FE block below runs on
        * the full data (the leave-one-out loop left the small results table in
        * memory).
        use "`_panel_before_loo'", clear
        xtset market_id year

        * Wild cluster bootstrap on the expanded MAIN spec, run IMMEDIATELY after
        * the regression so the estimation sample is still intact (few clusters ->
        * conventional p over-rejects; the bootstrap p is the honest one).
        capture which boottest
        if _rc == 0 {
            estimates restore main_expanded
            boottest c.qual_rate#c.pre_exposure_z, reps(9999) cluster(cluster_id) ///
                boottype(wild) weighttype(rademacher) seed(20260708)
        }

        * -------------------- Region x year FE (benchmark-paper adaptation) ----
        * Paixao & Hartley (BoC SAN 2024-25), the closest analog to this design,
        * use province-by-time fixed effects (gamma_pt) rather than plain year FE,
        * to absorb province-level shocks non-parametrically. Full province x year
        * FE saturates our single-market provinces (MB, ON/QC, NS, NL), so we use
        * REGION x year FE with 5 regions (Atlantic, Quebec, Ontario, Prairies,
        * West), each containing multiple markets -- the well-identified analogue.
        *
        * IMPORTANT (reported honestly, not hidden): this specification yields a
        * significant NEGATIVE coefficient, BUT it FAILS a placebo pre-trends test
        * (the pre-2022 exposure interactions are jointly non-zero and trend the
        * OPPOSITE way to the post-2022 effect). That means its significance is a
        * continuation/reversal of a pre-existing regional divergence, NOT a causal
        * treatment effect. We therefore keep market+year FE (which has FLAT
        * pre-trends) as the PRIMARY spec, and report region x year FE only as a
        * transparency/robustness exercise that we explicitly do NOT interpret
        * causally. See the pre-trends test printed just below.
        capture drop region
        gen region = ""
        replace region = "Atlantic" if inlist(province, "NB", "NS", "NL", "PE")
        replace region = "Quebec"   if province == "QC"
        replace region = "Ontario"  if inlist(province, "ON", "ON/QC")
        replace region = "Prairies" if inlist(province, "AB", "SK", "MB")
        replace region = "West"     if province == "BC"
        capture drop region_year
        egen region_year = group(region year)

        xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.region_year, ///
            fe vce(cluster cluster_id)
        estimates store main_expanded_regionyr
        capture which boottest
        if _rc == 0 {
            boottest c.qual_rate#c.pre_exposure_z, reps(9999) cluster(cluster_id) ///
                boottype(wild) weighttype(rademacher) seed(20260708)
        }

        * PLACEBO PRE-TRENDS TEST for the region x year FE spec. If the pre-2022
        * exposure interactions are jointly non-zero, parallel trends FAILS and the
        * significant post coefficient above is NOT a clean treatment effect.
        xtreg affordability_gap ib2021.year##c.pre_exposure_z i.region_year, ///
            fe vce(cluster cluster_id)
        display as text ""
        display as text "Region x year FE -- placebo pre-trends test:"
        testparm i(2016/2020).year#c.pre_exposure_z
        display as text "If Prob > F is small, pre-trends FAIL -> do NOT interpret"
        display as text "the region x year FE coefficient causally (see note above)."

        * Robustness of the region-year result to the two mega-markets
        xtreg affordability_gap c.qual_rate#c.pre_exposure_z i.region_year ///
            if !inlist(cma_name, "Toronto", "Vancouver"), fe vce(cluster cluster_id)
        estimates store main_expanded_regionyr_notv
    restore
}
else {
    display as text ""
    display as text "Expanded panel not found; run 04b_expand_sample.do and"
    display as text "07_build_panel.do with global sample_mode = expanded first."
    display as text ""
}


* -------------------------- (8) Note on table output -----------------------
* All regressions above are recorded in the log. The formatted, paper-ready
* tables (summary stats, main + robustness, composite robustness) are written
* ONCE, by 11_paper_outputs.do via outreg2, to avoid duplicate table files in
* the output folder. Nothing is written to disk here.
display as text ""
display as text "Regressions complete. Formatted tables are written by 11_paper_outputs.do."

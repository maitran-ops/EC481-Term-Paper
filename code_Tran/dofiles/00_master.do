*==============================================================================
* 00_master.do  --  EC481 Final Analysis, Mai Tran
*------------------------------------------------------------------------------
*
* REQUIRED user-written commands (install once, needs internet):
*         ssc install estout       // esttab / estout / eststo tables
*         ssc install outreg2      // raw regression/summary tables (step 11)
*         ssc install boottest    // wild cluster bootstrap (few clusters)
*==============================================================================
* 00_master.do  --  run instructions below
*==============================================================================
*
* HOW TO RUN
*   1. Edit the ONE line marked  <<< EDIT  below to point at the FOLDER
*      that contains this file (i.e. the dofiles folder).
*   2. Edit the ONE line marked  <<< EDIT  in 01_globals.do to point at
*      the DATA folder (which contains raw/, clean/, output/).
*   3. Execute 00_master.do in Stata:
*        - Do-file Editor: press Ctrl+D (Windows/Linux) or Cmd+Shift+D (Mac).
*        - Command line:  do "C:/full/path/to/00_master.do"
*
*   Each numbered file can also be run standalone once the earlier ones
*   have produced their .dta outputs.
*
* IMPORTANT
*   - Use FORWARD SLASHES "/" in every path, not backslashes "\".
*   - Do NOT put a "$" in front of the drive letter. Just write "C:/...".
*   - Wrap the whole path in double quotes because it contains spaces.
*
*==============================================================================

clear all
set more off
capture log close


* ----- EDIT THIS LINE ONLY-----------------------------------------------------
global dofiles "C:\Users\Dell\OneDrive - Wilfrid Laurier University\Spring - 2026\EC 481\Term paper\Tran_EC481_submission\code_Tran\dofiles"    // <<< EDIT
* -----------------------------------------------------------------------------

* PRIMARY-SPEC TOGGLE: single board per CMA is the primary spec (default).
* Composite HPI is checked separately as a robustness exercise in
* 10_composite_robustness.do under three weight schemes -- it is NOT baked
* into the main panel. Leave this at 0 unless you specifically want the
* (approximate-weight) composite as the default main-panel HPI.
global use_composite_primary "0"


* Preflight: confirm 00_master's siblings are actually in $dofiles.
capture confirm file "$dofiles/01_globals.do"
if _rc {
    display as error " "
    display as error "*****************************************************"
    display as error "  Stata cannot find 01_globals.do inside $dofiles."
    display as error "  Fix the global dofiles line above so that the folder"
    display as error "  exists and contains 01_globals.do."
    display as error "*****************************************************"
    display as error " "
    display as error "  Current dofiles path: $dofiles"
    display as error " "
    exit 601
}

* Set project root and folders (raw/, clean/, output/)
do "$dofiles/01_globals.do"

* Open master log
log using "$output/ec481_final_Tran.log", replace text

* --- 1. Clean raw sources ---------------------------------------------------
do "$dofiles/02_clean_hpi.do"          // CREA MLS HPI, one row per board-year
do "$dofiles/03_crosswalk.do"          // CREA -> CMA crosswalk + baseline sample flag
do "$dofiles/04_composite_hpi.do"      // Household-weighted composite HPI for multi-board CMAs
do "$dofiles/04b_expand_sample.do"     // Append 5 CMA proxies -> 36-CMA panel
do "$dofiles/05_clean_income.do"       // T1FF median census-family income by CMA
do "$dofiles/06_clean_rates.do"        // BoC 5-yr rate + OSFI qualifying rate
do "$dofiles/06b_clean_controls.do"    // Housing starts + population + unemployment (mechanism-check controls)

* --- 2. Build analysis panels ----------------------------------------------
* The baseline 31-CMA panel is still built because 09_regressions.do runs the
* event study, long-difference, and leave-out checks on it. But we only produce
* FIGURES and TABLES for the final 36-CMA sample (below), to keep the output
* folder clean -- the baseline numbers are all visible in the log.
global sample_mode "baseline"
do "$dofiles/07_build_panel.do"        // -> core_affordability_panel_Tran.dta

global sample_mode "expanded"
do "$dofiles/07_build_panel.do"        // -> core_affordability_panel_expanded_Tran.dta
global sample_mode "baseline"          // reset for downstream defaults

* --- 3. Descriptives (36-CMA sample only) -----------------------------------
* Only the final 36-CMA figures and summary table are written to disk. Earlier
* builds produced both 31- and 36-market versions; we drop the 31-market figures
* so the output folder contains one clean, current set.
global fig_sample_mode "expanded"
do "$dofiles/08_figures_tables.do"     // Summary stats + 4 figures (36 CMAs)

* --- 4. Regressions (baseline + expanded) ----------------------------------
do "$dofiles/09_regressions.do"        // Baseline DiD, event study, long diff,
                                        // expanded 36-CMA (primary), leave-one-out
                                        // leverage diagnostic, wild bootstrap,
                                        // region x year FE + its pre-trends test

* --- 5. Composite HPI robustness (3 weight schemes, not the primary spec) --
do "$dofiles/10_composite_robustness.do"

* --- 6. Raw Stata output tables (outreg2) ------------------------------------
do "$dofiles/11_paper_outputs.do"      // tab1/2/3_..._Tran.doc (+ tex fragment)

log close

display as text " "
display as text "Pipeline finished."
display as text "Log:            $output/ec481_final_Tran.log"
display as text "Paper tables:   $output/tab1_summary_stats_Tran.doc"
display as text "                $output/tab2_main_results_Tran.doc (+ .tex)"
display as text "                $output/tab3_composite_robustness_Tran.doc"
display as text "Figures:        $output/fig1..fig4_Tran.png (36 CMAs)"
display as text "Clean panel:    $clean/core_affordability_panel_expanded_Tran.dta (36 CMAs)"

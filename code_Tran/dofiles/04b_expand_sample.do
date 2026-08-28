*==============================================================================
* 04b_expand_sample.do  --  Append 5 CMA proxy markets to reach the 36-CMA sample
*------------------------------------------------------------------------------
* Method (Progress Meeting 2 fallback #2)
*   Attach CMAs/CAs that have no exact-name CREA board to a proxy board, each
*   carrying a match_quality dummy so the reader sees the match is imperfect.
*   Two proxy types (CMA-only build; census agglomerations are excluded):
*     - proxy_multi_cma      : board covers the CMA plus other territory; the
*                              CMA is the dominant/anchor market (weight ~ 1).
*     - proxy_shared_hpi     : one board HPI serves two CMAs (Kelowna, Kamloops
*                              both use INTERIOR_BC). Distinct income/pop but
*                              SAME price series -> pool into one board cluster.
*
*   NOTE ON SAMPLE DEFINITION: an earlier build appended 3 census agglomerations
*   (Kawartha Lakes, North Bay, Sault Ste. Marie). They are DROPPED here so the
*   unit of analysis is a single consistent type (CMA). The result is a clean
*   36-CMA sample = 31 baseline CMAs + 5 CMA proxies. This covers 36 of Canada's
*   41 CMAs; the 5 omitted (Oshawa, Saguenay, Lethbridge, Thunder Bay, Red Deer)
*   have no separable CREA board series and cannot be built without contaminating
*   an existing series (Oshawa shares Toronto's TRREB board) or fabricating data.
*
* This file builds a SEPARATE expanded HPI panel. It does NOT overwrite the
* 31-market baseline. 07_build_panel.do reads whichever it is told to.
*
* Inputs
*   $dofiles/crosswalk_key_Tran.xlsx   (sheet Expansion_Markets)
*   $clean/hpi_annual_clean_Tran.dta
*   $clean/hpi_cma_clean_Tran.dta      (baseline 31-market HPI panel)
* Output
*   $clean/hpi_cma_expanded_Tran.dta   (36-CMA HPI panel + match_quality)
*
* Fallback
*   If the proxy board's HPI series is not in hpi_annual_clean (i.e. that
*   worksheet is absent from crea_hpi_Tran.xlsx), that market is skipped with
*   a note and the sample lands below 36. Nothing is fabricated.
*==============================================================================

capture confirm file "$dofiles/crosswalk_key_Tran.xlsx"
if _rc {
    display as error "crosswalk_key_Tran.xlsx not found in $dofiles. Skipping expansion."
    exit 0
}

* -------------------------- Load expansion map ------------------------------
import excel "$dofiles/crosswalk_key_Tran.xlsx", ///
    sheet("Expansion_Markets") firstrow clear
rename *, lower

keep crea_board matched_market market_type province match_method match_quality
foreach v in crea_board matched_market market_type province match_method match_quality {
    replace `v' = strtrim(itrim(`v'))
}
drop if missing(crea_board, matched_market)

* -------------------------- CMA-only enforcement ----------------------------
* This build is a CLEAN CMA sample. Drop any census agglomeration (CA) rows so
* the unit of analysis is a single consistent type. The crosswalk key should
* already contain only CMA rows, but this guard makes the intent explicit and
* stops a stray CA from silently entering the panel.
count if upper(market_type) == "CA"
if r(N) > 0 {
    display as text "Dropping `r(N)' census-agglomeration row(s) to keep a CMA-only sample."
    drop if upper(market_type) == "CA"
}
capture assert upper(market_type) == "CMA"
if _rc {
    display as error "Non-CMA market_type remains after filter; inspect crosswalk_key_Tran.xlsx."
    exit 459
}

* Board clustering label: markets sharing a board share a cluster
gen board_cluster = crea_board

tempfile expmap
save `expmap', replace

* -------------------------- Attach proxy HPI --------------------------------
* One board can map to more than one market (INTERIOR_BC -> Kelowna AND Kamloops),
* so crea_board is not unique in the expansion map. joinby duplicates each
* board's HPI rows across every market that maps to it -- exactly what we want.
* First, report any expansion board that has NO HPI series in the workbook.
use "$clean/hpi_annual_clean_Tran.dta", clear
replace crea_market = strtrim(itrim(crea_market))
rename crea_market crea_board
keep crea_board
duplicates drop
merge 1:m crea_board using `expmap'
levelsof crea_board if _merge == 2, local(missingboards)
foreach b of local missingboards {
    display as error "Expansion board `b' has no HPI series in crea_hpi_Tran.xlsx; market skipped."
}
drop _merge

* Now do the actual HPI attach via joinby (many HPI year-rows x market rows)
use "$clean/hpi_annual_clean_Tran.dta", clear
replace crea_market = strtrim(itrim(crea_market))
rename crea_market crea_board

joinby crea_board using `expmap'

keep if inrange(year, 2016, 2023)

rename matched_market cma_name
gen ln_benchmark_price = ln(benchmark_price)

keep crea_board cma_name market_type province match_method match_quality ///
     board_cluster year benchmark_price ln_benchmark_price
order crea_board cma_name market_type province match_quality board_cluster ///
      year benchmark_price ln_benchmark_price
sort cma_name year

* Sanity: each expansion market should have exactly the panel years present
bysort cma_name: gen _nyr = _N
tab cma_name _nyr
drop _nyr

tempfile expansion_hpi
save `expansion_hpi', replace

* -------------------------- Stack onto baseline -----------------------------
use "$clean/hpi_cma_clean_Tran.dta", clear

* Baseline markets are exact/PIP/manual: tag them and set board_cluster = market
capture confirm variable match_quality
if _rc gen match_quality = "baseline"
gen market_type = "CMA"
replace market_type = "CMA" if missing(market_type)
gen board_cluster = cma_name          // baseline markets each their own cluster
capture gen crea_board = crea_market

append using `expansion_hpi'

* Re-number market and cluster ids over the combined panel
capture drop market_id
capture drop cluster_id
capture label drop market_id
capture label drop cluster_id
egen market_id  = group(cma_name),      label(market_id,  replace)
egen cluster_id = group(board_cluster), label(cluster_id, replace)

* Diagnostics
egen tag_m = tag(market_id)
egen tag_c = tag(cluster_id)
count if tag_m == 1
display as text "Total markets:  " r(N)
count if tag_c == 1
display as text "Total clusters: " r(N)
tab match_quality if tag_m == 1
drop tag_m tag_c

* -------------------------- Tier-0 data-integrity checks --------------------
* These stop the pipeline loudly if the expanded panel is malformed, rather
* than letting a silent artifact flow into the regressions.
* (1) Balanced panel: every market must have exactly 8 years (2016-2023).
bysort market_id (year): gen _nyr = _N
capture assert _nyr == 8
if _rc {
    display as error "*** UNBALANCED PANEL: some market != 8 years. Inspect below. ***"
    tab cma_name if _nyr != 8
    drop _nyr
    exit 459
}
drop _nyr
* (2) No missing or non-positive benchmark prices.
capture assert !missing(benchmark_price) & benchmark_price > 0
if _rc {
    display as error "*** BAD HPI VALUES (missing or non-positive). Inspect below. ***"
    list cma_name year benchmark_price if missing(benchmark_price) | benchmark_price <= 0
    exit 459
}
* (3) Kelowna & Kamloops must carry the identical INTERIOR_BC series (shared HPI).
*     For each year, the two markets' benchmark prices should match exactly.
preserve
    keep if inlist(cma_name, "Kelowna", "Kamloops")
    collapse (max) bmax = benchmark_price (min) bmin = benchmark_price, by(year)
    capture assert reldif(bmax, bmin) < 1e-6
    if _rc {
        display as error "*** Kelowna/Kamloops HPI not identical -- shared-board attach failed. ***"
        list year bmin bmax
        exit 459
    }
restore
display as text "Data-integrity checks passed: 36 CMAs, balanced, clean HPI."

xtset market_id year
save "$clean/hpi_cma_expanded_Tran.dta", replace

display as text ""
display as text "Expanded HPI panel saved: hpi_cma_expanded_Tran.dta"
display as text "Kelowna and Kamloops share INTERIOR_BC -> one cluster."
display as text ""

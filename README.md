# Replication package — Monetary Tightening and the Affordability Gap Across Canadian Housing Markets

Mai Tran · EC481-J · Wilfrid Laurier University

## How to run

1. Open `dofiles/00_master.do` and `dofiles/01_globals.do`  and edit the single `global root` line so it points to
   the `code_Tran/dofiles` and `code_Tran/data` folder on your machine (a `<<< EDIT` marker flags the line).
   Everything else keys off that one path.
2. Open `dofiles/00_master.do` in Stata and run it. It executes every step below in order
   and writes all figures, tables, and the log to `data/output/`.

The required Stata packages are `outreg2`, `boottest`, and `estout` (`ssc install <name>` if missing).

## Folder structure

```
code_Tran/
├── dofiles/     all .do files (run 00_master.do)
├── data/
│   ├── raw/     original source data (CREA, T1FF, BoC, and the controls under raw/controls/)
│   ├── clean/   cleaned .dta files produced by the pipeline
│   └── output/  figures, tables, and ec481_final_Tran.log
```

## What each do-file does

| File | Purpose |
|------|---------|
| `00_master.do` | Master file — runs the whole pipeline in order. |
| `01_globals.do` | Sets the root path and folder globals. **Edit this first.** |
| `02_clean_hpi.do` | Cleans the CREA MLS HPI to one row per board-market and year. |
| `03_crosswalk.do` | Builds the CREA-board → CMA crosswalk and merges it into the HPI panel. |
| `04_composite_hpi.do` | Builds the household-weighted composite HPI for the multi-board CMAs. |
| `04b_expand_sample.do` | Adds the five proxy CMAs to reach the 36-CMA sample. |
| `05_clean_income.do` | Cleans T1FF median census-family income by CMA. |
| `06_clean_rates.do` | Builds the Bank of Canada 5-year rate and the OSFI qualifying rate. |
| `06b_clean_controls.do` | Builds the mechanism-check controls (housing starts, population, unemployment) from the original downloads. |
| `07_build_panel.do` | Assembles the final CMA-by-year panel. Run twice (baseline, then expanded). |
| `08_figures_tables.do` | Produces the summary statistics and the four descriptive figures. |
| `09_regressions.do` | Main regressions, robustness, event study, mechanism check, and extension. |
| `10_composite_robustness.do` | Composite-HPI robustness under three weighting schemes. |
| `11_paper_outputs.do` | Writes the raw Stata output tables (Tables 1–3) via `outreg2`. |

Run `00_master.do` once and every output in the paper is reproduced.

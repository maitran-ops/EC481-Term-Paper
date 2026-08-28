# EC481-Term-Paper
# Monetary Tightening and the Affordability Gap Across Canadian Housing Markets

**Author:** Mai Tran  
**Course:** EC 481 — Economics Research Paper & Seminar, Wilfrid Laurier University  
**Date:** August 2026  
**Grade:** A

## Summary

This paper investigates whether the Bank of Canada's post-2022 interest rate increases disproportionately widened the gap between home prices and mortgage-qualified purchasing capacity in markets that were already expensive relative to local income. Using a purpose-built panel of 36 census metropolitan areas (2016–2023), I apply a continuous-treatment difference-in-differences model with two-way fixed effects and find a precisely estimated near-zero effect — the tightening compressed affordability by a similar magnitude across both expensive and affordable markets.

## Methods

- Constructed a CMA-level panel linking CREA MLS HPI benchmark prices, Statistics Canada T1FF median family income, and Bank of Canada posted mortgage rates under the OSFI stress-test qualifying rule
- Estimated a continuous-treatment difference-in-differences specification with market and year fixed effects, clustered at the real-estate board level
- Validated results with wild cluster bootstrap inference (Rademacher weights, 9,999 replications), event-study diagnostics, leave-one-out sensitivity analysis, and robustness checks across three alternative house-price index constructions
- Conducted mechanism checks with time-varying supply and demand controls (housing starts, population, unemployment)

## Key Finding

The exposure interaction coefficient is small, negative, and statistically insignificant (β̂ = −0.015, p = 0.26; wild-bootstrap p = 0.39). The result approaches zero when Toronto, Vancouver, or all of British Columbia are excluded, indicating the gradient is driven by two structurally atypical markets rather than a systematic pattern. The 2022–2023 affordability deterioration was national in scope, not concentrated in the most stretched cities.

## Repository Contents

- `Mai_Tran_EC481_final.pdf` — Full research paper
- `code/` — Stata do-files for data construction, estimation, and figure generation
- `data/` — Cleaned panel dataset and crosswalk files

## Tools

Stata, ArcGIS (spatial crosswalk), LaTeX

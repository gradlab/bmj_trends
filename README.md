# SAS code used in Olesen et al. BMJ 2018

"Trends in outpatient antibiotic use and prescribing practice among US older adults, 2011-15: observational study"
*BMJ* 2018;362:k3155 doi:[10.1136/bmj.k3155](https://doi.org/10.1136/bmj.k3155)

## Using these files

First and foremost, these files were not intended to be user-friendly. They are
configured to extract data on the particular server where Medicare data was
stored during the execution of this project.

However, the database files and the code describing the models should be useful
for someone intending to replicate the results. 

## Files

- `db/` contains files that include ICD-9 codes, Fleming-Dutra appropriateness tiers, antibiotic names, etc.
- `clean_db.sas` turns those reference files into SAS libraries
- `clean_bene.sas` extracts some beneficiary information and saves it as a SAS library
- `clean_pde.sas` uses the beneficiary library and DB libraries to extract antibiotic PDEs
- `clean_dx.sas` is similar, for encounter information
- `analysis.sas` runs most of the analysis on the beneficiary and PDE data
- `analysis_rxdx.sas` runs the drug-diagnosis models

## Author

Scott Olesen <olesen@hsph.harvard.edu>

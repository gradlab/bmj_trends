dm 'clear log';

ods select none;
option obs=max;

%let working_dir=XXX; * Need to insert the data directory here;

* Which antibiotics are used to treat which site;
data antibiotic_site;
infile datalines dsd missover delimiter=',';
input antibiotic :$32. site :$32.;
cards;
azithromycin,respiratory
levofloxacin,respiratory
amoxicillin/clavulanate,respiratory
ciprofloxacin,gi
metronidazole,gi
levofloxacin,gi
cephalexin,ssti
trimethoprim/sulfamethoxazole,ssti
ciprofloxacin,ssti
ciprofloxacin,uti
nitrofurantoin,uti
trimethoprim/sulfamethoxazole,uti
;
run;

* Which diagnoses are present at each site;
data dx_site;
infile datalines dsd missover delimiter=',';
input dx_cat :$32. site :$32.;
cards;
pneumonia,respiratory
sinusitis,respiratory
bronchitis,respiratory
uri,respiratory
asthma,respiratory
other_resp,respiratory
uti,uti
uti_t3,uti
gi,gi
gi_t3,gi
ssti,ssti
ssti_t3,ssti
;
run;

* Mapping from antibiotic to site to diagnosis;
proc sql;
create table antibiotic_site_dx as
select antibiotic, A.site, dx_cat
from antibiotic_site A
inner join dx_site B
on A.site = B.site;
quit;

proc sql noprint;

create table my_lib.dx_counts as
select year, dx_cat, count(*) as n_dx
from my_lib.dx
group by year, dx_cat;

create table pde_dx as
select
  A.year, A.bene_id,
  pde_id, pde_date, antibiotic,
  encounter_date, B.dx_cat, case
    when encounter_date is null then 4
    when B.dx_cat eq 'remaining_codes' then 3
	else C.tier end as tier
from my_lib.pde(sortedby=year bene_id pde_date) A
left join my_lib.dx(sortedby=year bene_id encounter_date) B
on A.year = B.year
and A.bene_id = B.bene_id
and pde_date - encounter_date between 0 and 7
left join my_lib.fd_tiers C on B.dx_cat = C.dx_cat
where A.year between 2011 and 2014
and A.fill_number = 0
order by A.year, A.bene_id, pde_id;

* Compute the appropriateness of each PDE;
create table pde_approp as
select year, bene_id, pde_id,
  case
    when min(tier) = 4 then 'indeterminate'
    when min(tier) = 3 then 'inappropriate'
    when min(tier) < 3 then 'appropriate'
    else 'bad_value' end
  as appropriateness
from pde_dx(sortedby=year bene_id pde_id)
group by year, bene_id, pde_id;

* Summarize appropriate use by beneficiary;
create table bene_pde_approp as
select A.*,
  coalesce(n_pde_appropriate, 0) as n_pde_appropriate,
  coalesce(n_pde_inappropriate, 0) as n_pde_inappropriate,
  coalesce(n_pde_indeterminate, 0) as n_pde_indeterminate
from my_lib.bene A
left join (select year, bene_id, count(*) as n_pde_appropriate   from pde_approp where appropriateness = 'appropriate'   group by year, bene_id) B on A.year = B.year and A.bene_id = B.bene_id
left join (select year, bene_id, count(*) as n_pde_inappropriate from pde_approp where appropriateness = 'inappropriate' group by year, bene_id) C on A.year = C.year and A.bene_id = C.bene_id
left join (select year, bene_id, count(*) as n_pde_indeterminate from pde_approp where appropriateness = 'indeterminate' group by year, bene_id) D on A.year = D.year and A.bene_id = D.bene_id
order by year, bene_id;

quit;

/* Count appropriate use */
proc sql noprint;
create table my_lib.approp_counts as
select year, appropriateness, count(*) as n_pde
from pde_approp
group by year, appropriateness;
quit;

/* Appropriateness models */
proc sql noprint;
create table my_lib.approp_models (
  appropriateness char(50),
  estimate num format=D12.9,
  lower_ci num format=D12.9,
  upper_ci num format=D12.9,
  p_value  num format=D12.9
);
quit;

* Start with all PDEs, but only for 2011-2014;
proc sql noprint;
create table work_abx as
select A.*, coalesce(n, 0) as y
from my_lib.bene A
left join (
  select year, bene_id, count(*) as n
  from my_lib.pde
  where fill_number = 0
  group by year, bene_id
) B
on A.year = B.year and A.bene_id = B.bene_id
where A.year between 2011 and 2014;
quit;

proc genmod data=work_abx;
  class sex race region age_group;
  model y = year sex race region age_group dual n_cc / dist=poisson link=log;
  ods output Estimates=work_est;
  estimate "nyear" year 3 / exp;
run;

proc sql noprint;
insert into my_lib.approp_models
select
  "overall3" as antibiotic,
  MeanEstimate as estimate,
  MeanLowerCL as lower_ci,
  MeanUpperCL as upper_ci,
  ProbChiSq as p_value
from work_est
where Label eq "nyear";
quit;

%macro approp_model(approp, n_years);
* Create working table;
proc sql noprint;
create table work1 as
select A.*, coalesce(n, 0) as y
from my_lib.bene A
left join (
  select year, bene_id, count(*) as n
  from pde_approp
  where appropriateness=&approp
  group by year, bene_id
) B
on A.year = B.year and A.bene_id = B.bene_id
where A.year between 2011 and 2014;
quit;

* Run the model;
proc genmod data=work1;
  class sex race region age_group;
  model y = year sex race region age_group dual n_cc / dist=poisson link=log;
  ods output Estimates=work_est;
  estimate "nyear" year &n_years / exp;
run;

proc sql noprint;
insert into my_lib.approp_models
select
  &approp as appropriateness,
  MeanEstimate as estimate,
  MeanLowerCL as lower_ci,
  MeanUpperCL as upper_ci,
  ProbChiSq as p_value
from work_est
where Label eq "nyear";
quit;

%mend;

%approp_model("appropriate", 3);
%approp_model("inappropriate", 3);
%approp_model("indeterminate", 3);


/* PDE for dx */

proc sql noprint;
create table pde_for_dx as
select year, bene_id, pde_id, A.antibiotic, A.dx_cat, site
from pde_dx A
inner join antibiotic_site_dx B
on A.antibiotic = B.antibiotic
and A.dx_cat = B.dx_cat;
quit;

proc sort data=pde_for_dx;
by year bene_id pde_id site;
run;

/*
For each PDE, pick one diagnosis. If the same PDE could be used to treat
multiple sites (e.g., SXT for UTI and SSTI), pick one diagnosis per site.
*/
proc surveyselect
data=pde_for_dx out=pde_for_dx_single
noprint
method=urs N=1 outhits rep=1;
strata year bene_id pde_id site;
run;

data pde_for_dx_single;
set pde_for_dx_single (drop=NumberHits ExpectedHits SamplingWeight);
run;


/*
Table of pde for dx by year
*/
proc sql;
create table my_lib.pde_for_dx_counts as
select year, site, antibiotic, dx_cat, count(*) as n_pdedx
from pde_for_dx
group by year, site, antibiotic, dx_cat;

create table my_lib.pde_for_dx_single_counts as
select year, site, antibiotic, dx_cat, count(*) as n_pdedx
from pde_for_dx_single
group by year, site, antibiotic, dx_cat;
quit;

/*
Regressions of PDE for dx
*/
proc sql;

create table my_lib.pde_for_dx_models (
  antibiotic char(50),
  dx_cat char(50),
  estimate num format=D12.9,
  lower_ci num format=D12.9,
  upper_ci num format=D12.9,
  p_value  num format=D12.9
);

create table my_lib.pde_for_dx_single_models
like my_lib.pde_for_dx_models;
quit;

%macro pde_for_dx_model(in_data, out_data, abx, dx, n_years);

proc sql;
create table work1 as
select A.*, coalesce(n, 0) as y
from my_lib.bene A
left join (
  select year, bene_id, count(*) as n
  from &in_data
  where antibiotic="&abx" and dx_cat="&dx"
  group by year, bene_id
) B
on A.year = B.year and A.bene_id = B.bene_id
where A.year between 2011 and 2014;
quit;

proc genmod data=work1;
class sex race region age_group;
  model y = year sex race region dual n_cc age_group / dist=poisson link=log;
  ods output Estimates=work_est;
  estimate "nyear" year &n_years / exp;
run;

proc sql;
insert into &out_data
select
  "&abx" as antibiotic,
  "&dx" as dx_cat,
  MeanEstimate as estimate,
  MeanLowerCL as lower_ci,
  MeanUpperCL as upper_ci,
  ProbChiSq as p_value
from work_est
where Label eq "nyear";
quit;
%mend;

data _null_;
set antibiotic_site_dx;
call execute(cat('%pde_for_dx_model(pde_for_dx, my_lib.pde_for_dx_models, ', antibiotic, ', ', dx_cat, ', 3);'));
call execute(cat('%pde_for_dx_model(pde_for_dx_single, my_lib.pde_for_dx_single_models, ', antibiotic, ', ', dx_cat, ', 3);'));
run;


%macro write_tsv(data, fn);
proc export data=&data outfile=&fn
dbms=tab replace; run;
%mend;

%macro write_tsv2(data);
%write_tsv(my_lib.&data, "&working_dir\tables\&data..tsv");
%mend;

%write_tsv2(approp_counts);
%write_tsv2(approp_models);
%write_tsv2(dx_counts);
%write_tsv2(pde_for_dx_counts);
%write_tsv2(pde_for_dx_single_counts);
%write_tsv2(pde_for_dx_models);
%write_tsv2(pde_for_dx_single_models);

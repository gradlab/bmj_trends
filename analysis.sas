dm 'clear log';

option obs=max;
option spool;

%let working_dir=XXX; * Need to insert the data directory here;

%let top_abx=('azithromycin', 'ciprofloxacin', 'amoxicillin', 'cephalexin', 'levofloxacin', 'trimethoprim/sulfamethoxazole', 'amoxicillin/clavulanate', 'doxycycline', 'nitrofurantoin', 'clindamycin');

libname my_lib "&working_dir\data";

/* **************************
   POPULATION CHARACTERISTICS
   ************************** */

* Table of study population characteristics by year;
proc sql noprint;
create table my_lib.study_pop_chars as
      select year, 'n_bene'      as key, count(bene_id) as value from my_lib.bene                          group by year
union select year, 'mean_cc'     as key, mean(n_cc)     as value from my_lib.bene                          group by year
union select year, 'sd_cc'       as key, std(n_cc)      as value from my_lib.bene                          group by year
union select year, 'n_65-74'     as key, count(bene_id) as value from my_lib.bene where age_group='65-74'  group by year
union select year, 'n_75-84'     as key, count(bene_id) as value from my_lib.bene where age_group='75-84'  group by year
union select year, 'n_85-94'     as key, count(bene_id) as value from my_lib.bene where age_group='85-94'  group by year
union select year, 'n_95+'       as key, count(bene_id) as value from my_lib.bene where age_group='95+'    group by year
union select year, 'n_female'    as key, count(bene_id) as value from my_lib.bene where sex='female'       group by year
union select year, 'n_white'     as key, count(bene_id) as value from my_lib.bene where race='white'       group by year
union select year, 'n_dual'      as key, count(bene_id) as value from my_lib.bene where dual=1             group by year
union select year, 'n_south'     as key, count(bene_id) as value from my_lib.bene where region='South'     group by year
union select year, 'n_midwest'   as key, count(bene_id) as value from my_lib.bene where region='Midwest'   group by year
union select year, 'n_west'      as key, count(bene_id) as value from my_lib.bene where region='West'      group by year
union select year, 'n_northeast' as key, count(bene_id) as value from my_lib.bene where region='Northeast' group by year
;
quit;

* Regressions for study population characteristics;
proc sql noprint;
create table my_lib.pop_char_models (
  pop_char char(50),
  estimate num format=D12.9,
  lower_ci num format=D12.9,
  upper_ci num format=D12.9,
  p_value  num format=D12.9
);
quit;

%macro poisson_model(in_data, pop_char, n_years);

proc genmod data=&in_data;
  model y = year / dist=poisson link=log;
  weight w;
  ods output Estimates=tmp_est;
  estimate "nyear" year &n_years / exp;
run;

proc sql noprint;
insert into my_lib.pop_char_models
select
  &pop_char as pop_char,
  MeanEstimate as estimate,
  MeanLowerCL as lower_ci,
  MeanUpperCL as upper_ci,
  ProbChiSq as p_value
from tmp_est
where Label eq "nyear";
quit;

%mend;

* No. beneficiaries has no weights, just 4 numbers;
proc sql noprint;
create table work_pop_char as
select year, count(*) as y, 1 as w
from my_lib.bene
group by year;
quit;

%poisson_model(work_pop_char, "n_bene", 4);

* No. chronic conditions is weighted by people;
proc sql noprint;
create table work_pop_char as
select year, n_cc as y, count(*) as w
from my_lib.bene
group by year, n_cc;
quit;

%poisson_model(work_pop_char, "ncc", 4);

/* All the rest of the models are proportions and followed a common
format */

%macro logbin_model(label, key, value, n_years);

proc sql;
create table work1 as
select year, y, count(*) as w
from (select *, &key=&value as y from my_lib.bene)
group by year, y;
quit;

proc genmod data=work1;
  model y(event='1') = year / dist=binomial link=log;
  weight w;
  ods output Estimates=tmp_est;
  estimate "nyear" year &n_years / exp;
run;

proc sql noprint;
insert into my_lib.pop_char_models
select
  &label as pop_char,
  MeanEstimate as estimate,
  MeanLowerCL as lower_ci,
  MeanUpperCL as upper_ci,
  ProbChiSq as p_value
from tmp_est
where Label eq "nyear";
quit;

%mend;

%logbin_model("pct_65-74", age_group, "65-74", 4);
%logbin_model("pct_75-84", age_group, "75-84", 4);
%logbin_model("pct_85-94", age_group, "85-94", 4);
%logbin_model("pct_95+",   age_group, "95+", 4);
%logbin_model("pct_female", sex, "female", 4);
%logbin_model("pct_white", race, "white", 4);
%logbin_model("pct_dual", dual, 1, 4);
%logbin_model("pct_south", region, "South", 4);
%logbin_model("pct_midwest", region, "Midwest", 4);
%logbin_model("pct_west", region, "West", 4);
%logbin_model("pct_northeast", region, "Northeast", 4);


/* ***********
   DRUG MODELS
   *********** */

* Counts for individual drugs;
proc sql noprint;
create table my_lib.claims_by_abx as
select year, antibiotic, count(*) as n_pde
from my_lib.pde
where antibiotic in &top_abx
and fill_number = 0
group by year, antibiotic;

insert into my_lib.claims_by_abx
select year, 'n_pde' as antibiotic, count(*) as n_pde
from my_lib.pde
where fill_number = 0
group by year;

insert into my_lib.claims_by_abx
select year, 'n_pde_top10' as antibiotic, count(*) as n_pde
from my_lib.pde
where fill_number = 0 and antibiotic in &top_abx
group by year;
quit;

* Models for individual drugs;
proc sql noprint;
create table my_lib.abx_models (
  antibiotic char(50),
  estimate num format=D12.9,
  lower_ci num format=D12.9,
  upper_ci num format=D12.9,
  p_value  num format=D12.9
);
quit;

%macro abx_model_base(in_data, label, n_years);

proc genmod data=&in_data;
  class sex race region age_group;
  model y = year sex race region age_group dual n_cc / dist=poisson link=log;
  ods output Estimates=work_est;
  estimate "nyear" year &n_years / exp;
run;

proc sql noprint;
insert into my_lib.abx_models
select
  &label as antibiotic,
  MeanEstimate as estimate,
  MeanLowerCL as lower_ci,
  MeanUpperCL as upper_ci,
  ProbChiSq as p_value
from work_est
where Label eq "nyear";
quit;

%mend;

* Overall model;
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
on A.year = B.year and A.bene_id = B.bene_id;
quit;

%abx_model_base(work_abx, "n_abx", 4);

%macro abx_model(abx, n_years);

proc sql noprint;
create table work_abx as
select A.*, coalesce(n, 0) as y
from my_lib.bene A
left join (
  select year, bene_id, count(*) as n
  from my_lib.pde
  where antibiotic = &abx
  and fill_number = 0
  group by year, bene_id
) B
on A.year = B.year and A.bene_id = B.bene_id;
quit;

%abx_model_base(work_abx, &abx, &n_years);

%mend;

%abx_model("azithromycin", 4);
%abx_model("ciprofloxacin", 4);
%abx_model("amoxicillin", 4);
%abx_model("cephalexin", 4);
%abx_model("trimethoprim/sulfamethoxazole", 4);
%abx_model("levofloxacin", 4);
%abx_model("amoxclav", 4);
%abx_model("doxycycline", 4);
%abx_model("nitrofurantoin", 4);
%abx_model("clindamycin", 4);

/* ********************
   SUBPOPULATION MODELS
   ******************** */

* Table of claims by bene and by subpopulation;
proc sql noprint;

create table bene_pde as
select A.*, coalesce(n, 0) as n_pde
from my_lib.bene A
left join (
  select year, bene_id, count(*) as n
  from my_lib.pde
  where fill_number = 0
  group by year, bene_id
) B
on A.year = B.year and A.bene_id = B.bene_id;

create table my_lib.claims_by_subpop as
      select year, 'overall' as pop_char,   'overall' as value, count(bene_id) as n_bene, sum(n_pde) as n_pde from bene_pde group by year
union select year, 'age_group' as pop_char, age_group as value, count(bene_id) as n_bene, sum(n_pde) as n_pde from bene_pde group by year, age_group
union select year, 'sex' as pop_char,       sex as value,       count(bene_id) as n_bene, sum(n_pde) as n_pde from bene_pde group by year, sex
union select year, 'race' as pop_char,      race as value,      count(bene_id) as n_bene, sum(n_pde) as n_pde from bene_pde group by year, race
union select year, 'region' as pop_char,    region as value,    count(bene_id) as n_bene, sum(n_pde) as n_pde from bene_pde group by year, region
;

create table my_lib.subpop_models (
  pop_char character(32),
  value character(32),
  estimate numeric,
  lower_ci numeric,
  upper_ci numeric,
  p_value numeric
);
quit;

* Regressions by subpopulation;

%macro subpop_model(pop_char, value, covars, n_years);

proc sql noprint;
create table work1 as
select *
from bene_pde
where &pop_char="&value";
quit;

proc genmod data=work1;
  class age_group sex race region;
  model n_pde = year dual n_cc &covars / dist=poisson link=log;
  ods output Estimates=work_est;
  estimate "nyear" year &n_years / exp;
run;

proc sql noprint;
insert into my_lib.subpop_models
select
  "&pop_char" as pop_char,
  "&value" as value,
  MeanEstimate as estimate,
  MeanLowerCL as lower_ci,
  MeanUpperCL as upper_ci,
  ProbChiSq as p_value
from work_est
where Label eq "nyear";
quit;

%mend;

%subpop_model(age_group, 65-74, sex race region, 4);
%subpop_model(age_group, 75-84, sex race region, 4);
%subpop_model(age_group, 85-94, sex race region, 4);
%subpop_model(age_group, 95+,   sex race region, 4);

%subpop_model(sex, female, age_group race region, 4);
%subpop_model(sex, male,   age_group race region, 4);

%subpop_model(race, white, age_group sex region, 4);
%subpop_model(race, black, age_group sex region, 4);
%subpop_model(race, Hispanic, age_group sex region, 4);
%subpop_model(race, other, age_group sex region, 4);

%subpop_model(region, Northeast, age_group sex race, 4);
%subpop_model(region, South, age_group sex race, 4);
%subpop_model(region, Midwest, age_group sex race, 4);
%subpop_model(region, West, age_group sex race, 4);


* Get number of unique benes and print to log;
proc sql noprint;
select count(distinct bene_id)
into :n_unique_bene
from my_lib.bene;
quit;

%put &=n_unique_bene;

%macro write_tsv(data, fn);
proc export data=&data outfile=&fn
dbms=tab replace; run;
%mend;

%macro write_tsv2(data);
%write_tsv(my_lib.&data, "&working_dir\tables\&data..tsv");
%mend;

%write_tsv2(study_pop_chars);
%write_tsv2(pop_char_models);
%write_tsv2(claims_by_abx);
%write_tsv2(abx_models);
%write_tsv2(claims_by_subpop);
%write_tsv2(subpop_models);

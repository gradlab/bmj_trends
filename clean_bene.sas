/*
Find all beneficiaries that are in the 20% sample. Merge with
the MBSF Part D to get plan coverage.

Keep beneficiaries that are:
  1. in 20% sample
  2. 65 or older
  3. Have 12 months of Parts A, B, and D coverage
     but zero HMO months (Medicare Advantage)
  4. Have known state (50 states & DC) and sex (male or female) 
*/

dm 'clear log';

option obs=max;
option spool;

%let input_dir=XXX;
%let working_dir=XXX;

libname denom "&input_dir\Denominator";
libname cclib "&input_dir\MBSF CC";
libname my_lib "&working_dir\data";

proc sql;
create table my_lib.bene (
  year integer,
  bene_id character(15),
  sex character(32),
  age integer,
  age_group character(32),
  race character(32),
  dual integer,
  n_cc integer,
  state character(32),
  region character(32),
  zipcode character(32)
);

create table my_lib.bene_log (
  year integer,
  step character(32),
  n_bene integer
);
quit;

%macro clean_year(year);

proc sql noprint;

create table bene1 as
select *
from denom.dnmntr&year;

insert into my_lib.bene_log
select &year as year, "total" as step, count(*) as n_bene
from bene1;

* Keep only benes in 20% sample;
delete from bene1
where not strctflg in ('05', '15');

insert into my_lib.bene_log
select &year as year, "20pct" as setp, count(*) as n_bene
from bene1;

* Keep only those 65 and up (age is at END of year);
delete from bene1
where not age >= 66;

insert into my_lib.bene_log
select &year as year, "over65" as setp, count(*) as n_bene
from bene1;

* Keep only benes w/ 12 months of A, B, and D coverage;
create table bene2 as
select A.*
from bene1 A
inner join (
  select bene_id
  from denom.mbsf_d&year
  where plncovmo = '12'
) B
on A.bene_id = B.bene_id
where (
      hmo_mo = 0
  and a_mo_cnt = 12
  and b_mo_cnt = 12
);

insert into my_lib.bene_log
select &year as year, "abd" as setp, count(*) as n_bene
from bene2;

* Keep only benes with sex info and in one of 50 states;
create table bene3 as
select A.*, state, region
from bene2 A
inner join my_lib.state_codes B on A.state_cd = B.state_cd
where sex in ('1', '2');

insert into my_lib.bene_log
select &year as year, "demo" as setp, count(*) as n_bene
from bene3;

* Get chronic conditions for these benes;
create table cc as
select
  bene_id,
  AMI + ATRIALFB + CATARACT + COPD + GLAUCOMA + HIPFRAC + DEPRESSN +
    OSTEOPRS + STRKETIA + CNCRBRST + CNCRCLRC + CNCRPRST +
    CNCRLUNG + CNCRENDM + ANEMIA + ASTHMA + HYPERL + HYPERP +
    HYPERT + HYPOTH as n_cc
from (
  select
    A.bene_id,
    case when AMI=3 then 1 else 0 end as AMI,
    case when ATRIALFB=3 then 1 else 0 end as ATRIALFB,
    case when CATARACT=3 then 1 else 0 end as CATARACT,
    case when COPD=3 then 1 else 0 end as COPD,
    case when GLAUCOMA=3 then 1 else 0 end as GLAUCOMA,
    case when HIPFRAC=3 then 1 else 0 end as HIPFRAC,
    case when DEPRESSN=3 then 1 else 0 end as DEPRESSN,
    case when OSTEOPRS=3 then 1 else 0 end as OSTEOPRS,
    case when STRKETIA=3 then 1 else 0 end as STRKETIA,
    case when CNCRBRST=3 then 1 else 0 end as CNCRBRST,
    case when CNCRCLRC=3 then 1 else 0 end as CNCRCLRC,
    case when CNCRPRST=3 then 1 else 0 end as CNCRPRST,
    case when CNCRLUNG=3 then 1 else 0 end as CNCRLUNG,
    case when CNCRENDM=3 then 1 else 0 end as CNCRENDM,
    case when ANEMIA=3 then 1 else 0 end as ANEMIA,
    case when ASTHMA=3 then 1 else 0 end as ASTHMA,
    case when HYPERL=3 then 1 else 0 end as HYPERL,
    case when HYPERP=3 then 1 else 0 end as HYPERP,
    case when HYPERT=3 then 1 else 0 end as HYPERT,
    case when HYPOTH=3 then 1 else 0 end as HYPOTH
  from cclib.mbsf_cc&year A
  inner join (select bene_id from bene3) B
  on A.bene_id = B.bene_id
);

* Merge in ccs and write out sex, race, dual eligibility;
create table bene4 as
select
  &year as year,
  A.bene_id,
  case when sex = '1' then 'male'
       when sex = '2' then 'female' end as sex,
  age,
  case when age between 65 and 74 then '65-74'
       when age between 75 and 84 then '75-84'
       when age between 85 and 94 then '85-94'
       when age >= 95 then '95+'
       else 'other' end as age_group,
  case when rti_race_cd = '1' then 'white'
       when rti_race_cd = '2' then 'black'
	   when rti_race_cd = '5' then 'Hispanic'
	   else 'other' end as race,
  case when buyin_mo = 0 then 0 else 1 end as dual,
  n_cc,
  state,
  region,
  substr(bene_zip, 1, 5) as zipcode
from bene3 A
inner join cc B on A.bene_id = B.bene_id;

insert into my_lib.bene_log
select &year as year, "final" as setp, count(*) as n_bene
from bene4;

insert into my_lib.bene
select *
from bene4;

quit;

%mend;

%clean_year(2011);
%clean_year(2012);
%clean_year(2013);
%clean_year(2014);
%clean_year(2015);

proc sort data=my_lib.bene;
by year bene_id;
run;

proc export
data=my_lib.bene_log outfile="&working_dir\tables\clean_bene_log.tsv"
dbms=tab replace;
run;

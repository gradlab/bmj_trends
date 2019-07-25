/*
Extract antibiotic PDEs
  - Filter for benes
  - Filter for antibiotic GNNs
  - Filter for oral and injected GCDFs
  - Select unique bene/date/antibiotic combinations, taking the total days
    supply and the minimum fill number
*/

dm 'clear log';
option obs=max;
option spool;

%let input_dir=XXX;
%let working_dir=XXX;

libname partd "&input_dir\PartD";
libname my_lib "&working_dir\data";

proc sql noprint;
create table my_lib.pde (
  year integer,
  bene_id character(32),
  pde_date date,
  pde_id character(32),
  antibiotic character(32),
  days_supply integer,
  fill_number integer
);

create table my_lib.pde_log (
  year integer,
  step character(32),
  n_pde integer
);
quit;

%macro clean_pde(year);

proc sql noprint;

* Get all the PDEs that match these beneficiaries;
create table pde1 as
select A.year, A.bene_id, pde_id, srvc_dt as pde_date,
  dayssply as days_supply, fill_num as fill_number, C.gnn as generic_name, C.gcdf
from my_lib.bene A
inner join partd.pdesaf&year B on A.bene_id = B.bene_id
inner join partd.formulary_&year C on B.formulary_id = C.formulary_id and B.frmlry_rx_id = C.frmlry_rx_id
where A.year = &year;

insert into my_lib.pde_log
select &year as year, "total" as step, count(*) as n_pde
from pde1;

* Keep only the antibiotics;
create table pde2 as
select A.*, antibiotic
from pde1 A
inner join my_lib.abx_class B on A.generic_name = B.generic_name;

insert into my_lib.pde_log
select &year as year, "abx" as step, count(*) as n_pde
from pde2;

* Keep only oral/injected;
create table pde3 as
select A.*
from pde2 A
inner join my_lib.oral_injected B on A.gcdf = B.gcdf;

insert into my_lib.pde_log
select &year as year, "oral_injected" as step, count(*) as n_pde
from pde3;

* Keep only unique bene/drug/day combinations;
create table pde4 as
select bene_id, min(pde_id) as pde_id, pde_date, antibiotic,
  sum(days_supply) as days_supply, min(fill_number) as fill_number
from pde3
group by bene_id, pde_date, antibiotic
order by bene_id, pde_date, pde_id;

insert into my_lib.pde_log
select &year as year, "one_per_day" as step, count(*) as n_pde
from pde4;

* Put work rows into the final table;
insert into my_lib.pde
select &year as year, bene_id, pde_date, pde_id, antibiotic, days_supply, fill_number
from pde4;

quit;

%mend;

%clean_pde(2011);
%clean_pde(2012);
%clean_pde(2013);
%clean_pde(2014);
%clean_pde(2015);

proc sort data=my_lib.pde;
by year bene_id pde_date antibiotic;
run;

proc export
data=my_lib.pde_log outfile="&working_dir\tables\clean_pde_log.tsv"
dbms=tab replace;
run;

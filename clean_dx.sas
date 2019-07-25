/* Get the diagnosis information: Carrier, Outpatient, Inpatient, SNF */

dm 'clear log';

option obs=max;
option spool;

%let input_dir=XXX;
%let working_dir=XXX;

libname car_lib "&input_dir\Carrier";
libname op_lib "&input_dir\Outpatient";
libname ip_lib "&input_dir\Inpatient";
libname snf_lib "&input_dir\SNF";
libname my_lib "&working_dir\data";

proc sql noprint;
create table my_lib.dx (
  year integer,
  bene_id character(32),
  encounter_date date,
  dx_cat character(32)
);
quit;

%macro set_select_line(n, var, from, bene, date_var);
%let &var =
select distinct A.bene_id, &date_var as encounter_date, coalesce(dx_cat, 'remaining_codes') as dx_cat
from &from A
inner join &bene.(sortedby=bene_id) B on A.bene_id = B.bene_id
left join my_lib.fd_codes C on A.icd_dgns_cd&n = C.code
where icd_dgns_cd&n is not null
and &date_var is not null;
%mend;

%macro set_select_lines(var, from, bene, n_dx, date_var);
%global line;
%local lines;

%set_select_line(1, line, &from, &bene, &date_var);
%let lines=&line;

%do i = 2 %to &n_dx;
  %set_select_line(&i, line, &from, &bene, &date_var);
  %let lines=&lines union &line;
%end;

%let &var=
select distinct bene_id, encounter_date, dx_cat
from (&lines);

%mend;

%macro clean_dx(year);

proc sql noprint;
create table tmp_bene as
select bene_id
from my_lib.bene
where year = &year
order by bene_id;
quit;

%global car op ip hospice snf;
%set_select_lines(car, car_lib.bcarclms&year, tmp_bene, 12, thru_dt);
%set_select_lines(op,  op_lib.otptclms&year,  tmp_bene, 25, thru_dt);
%set_select_lines(ip,  ip_lib.inptclms&year,  tmp_bene, 25, dschrgdt);
%set_select_lines(snf, snf_lib.snfclms&year,  tmp_bene, 25, dschrgdt);

proc sql noprint;

%put CAR %sysfunc(time(), time.) %sysfunc(date(), worddate.);
create table work_dx as
&car;

%put OP %sysfunc(time(), time.) %sysfunc(date(), worddate.);
insert into work_dx
&op;

%put IP %sysfunc(time(), time.) %sysfunc(date(), worddate.);
insert into work_dx
&ip;

%put SNF %sysfunc(time(), time.) %sysfunc(date(), worddate.);
insert into work_dx
&snf;

%if &year=2015 %then %do;
delete
from work_dx
where qtr(encounter_date) = 4;
%end;

quit;

proc sort data=work_dx noduprecs;
by bene_id encounter_date dx_cat;
run;

proc sql noprint;
insert into my_lib.dx
select &year as year, *
from work_dx;
quit;

%mend;

%clean_dx(2011);
%clean_dx(2012);
%clean_dx(2013);
%clean_dx(2014);
%clean_dx(2015);

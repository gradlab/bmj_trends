/*
Turn all the db files into nice SAS libraries that are easy to load
*/

dm 'clear log';

option obs=max;
option spool;

%let working_dir=XXX; * Need to insert the data directory here;

libname my_lib "&working_dir\data";

* Read in state codes;
DATA my_lib.state_codes ;
LENGTH
 state_cd $ 2
 state $ 20
 region $ 9
;

INFILE  "&working_dir\db\state_codes_data.txt"
     DSD
     LRECL=39;
INPUT
 state_cd
 state
 region $
;
RUN;

* Read in antibiotic names;
DATA my_lib.abx_class ;
LENGTH
 generic_name $ 30
 antibiotic $ 31
 antibiotic_class $ 48
;

INFILE  "&working_dir\db\abx_class_data.txt"
     DSD
     LRECL= 110 ;
INPUT
 generic_name
 antibiotic
 antibiotic_class $
;
RUN;

* New antibiotic use groups;
data my_lib.consumption_groups;
length
 antibiotic $ 29
 drug_group $ 15
;
infile "&working_dir\db\consumption_groups.txt"
 dsd
 lrecl=50;
input
 antibiotic
 drug_group $
;
run;

* Oral/injected route codes;
%macro read_tsv(fn, dat);
proc import datafile=&fn out=&dat
dbms=tab replace;
guessingrows=100000;
run;
%mend;

%read_tsv("&working_dir\db\oral_injected_codes.txt", my_lib.oral_injected);

* HCPCS E&M codes;
DATA my_lib.hcpcs_codes ;
LENGTH
 hcpcs_cd $ 5
 hcpcs_desc $ 33
;

INFILE  "&working_dir\db\hcpcs_data.txt"
     DSD
     LRECL= 47 ;
INPUT
 hcpcs_cd
 hcpcs_desc $
;
RUN;

* Fleming-Dutra ICD codes, categories, and tiers;
DATA  fd_data;
LENGTH
 code $ 7
 dx_cat $ 14
 version $ 1
;

INFILE  "&working_dir\db\fd_data.txt"
     DSD
     LRECL=36;
INPUT
 code
 dx_cat
 tier
 version $
;
RUN;

* keep only ICD9;
proc sql;
create table my_lib.fd_codes as
select code, dx_cat
from fd_data
where version = '9';
quit;

* FD tiers;
proc sql;
create table my_lib.fd_tiers as
select distinct dx_cat, tier
from fd_data;
quit;

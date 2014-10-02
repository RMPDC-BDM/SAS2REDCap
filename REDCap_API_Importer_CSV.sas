/******************************************************************************
PROGRAM NAME:  REDCap_API_Importer_CSV.sas

PRIMARY MACRO:  CSVIMPORT(data=, dir=, token=, url=, filesize=, overwriteBehavior=, returnContent=)

SAS Version:	9.3

REDCap Version:5.0.15

PURPOSE:			MACRO: Read a SAS dataset and import it into REDCap using CSV formatting

INPUT FILES:	SAS dataset of choice which is ready to be imported into REDCap

OUTPUT FILES:	&dir.\API_IMPORT_CSV\in.csv, &dir.\API_IMPORT_CSV\out.csv, &dir.\API_IMPORT_CSV\status.txt

AUTHOR:			Randy Burnham
TITLE:			Statistical Research Specialist

CO-AUTHOR:		Jason Lones
TITLE:			Clinical Data Manager | Data Storage Administrator | REDCap Administrator

ORGANIZATION:	Rocky Mountain Poison and Drug Center, Denver, CO

DATE CREATED: 	04/10/2014
*******************************************************************************/

*-------------------------------------------------------------------------------
* API IMPORTER (CSV version):::Name of Primary MACRO: 'CSVIMPORT'
*-------------------------------------------------------------------------------;
**MACRO Parameters
REQUIRED:
	data					="REDCap ready" SAS dataset (must be in EXACT formatting as in REDCap database)
	dir					=UNQUOTED filepath to the directory that you want the API import information dumped into
	token					=User and Project specific token acquired from REDCap
	url					=REDCap specific URL for your site (you can incorporate this into the code once comfortable)

OPTIONAL (Defaulted if not specified):
	filesize				=Filesize you would like to limit for the 'CSV in file' imported into REDCap (Recommended ~ 400kb)
	overwriteBehavior	=API parameter for overwrite behavior in REDCap (values=normal | overwrite)
	returnContent  	=Specify what REDCap should return in the "out" files (values=count | ids | nothing)

**NOTES on Importing Issues:
	- REDCap data that contain leading zero values pose issues with API importing. In order to resolve this,
	  re-format the variables in the SAS dataset to contain leading zero values (i.e. a format of z2.). One
	  could also edit the REDCap format of the variables to not have leading zero values. Make sure the SAS 
	  format matches the REDCap format.
	- Data containing "&" or "+" values may have issues with API importing.
		-Specifically, 
			- "&" stops the API import process within the current version of REDCap
				***TO RESOLVE THIS: Replace all '&' in the data with %26 (URL Encoded Character)
			- "+" does not appear in data when using the API, instead blank values are inserted
				***TO RESOLVE THIS: Replace all '+' in the data with %2B (URL Encoded Character)
	- Filesize issues arise when an "in" file exceeds 500kb, split the data up to be under this amount prior
	  to importing. A suggested 'safe' filesize is about 400kb, however this may depend on what you're server 
	  requirements are.
	- Missing values need to be changed to "" rather than '.'. This MACRO handles this for you.
	- If permanent formats are created within datasteps, make sure the dataset being sent to REDCap
	  is the data that REDCap expects. Strip new formats that were created and make sure all date variables within
	  your dataset have the format "YYMMDD.". REDCap is picky on what data it takes (this is a good thing).
	- Also make sure within REDCap the API abilities and 'Create Records' permissions are turned on, otherwise
	  you will get a 403 error when executing the macro.
*-------------------------------------------------------------------------------;

*-------------------------------------------------------------------------------
* MACRO: Creates REDCap CSV formatted API parameter file
*-------------------------------------------------------------------------------;
%macro masterCSV(data=, file=, overwriteBehavior=normal, returnContent=count, token=);
	/*	Create API Parameter row*/
		data _NULL_;
			file &file. lrecl=1073741823;
			put "%NRStr(content=record&format=csv&type=flat&returnformat=csv&returnContent=)&returnContent.%NRStr(&overwriteBehavior=)&overwriteBehavior.%NRStr(&)token=&token.%NRStr(&)data=";
		run;
		proc export data=&data. outfile="&dir.\API_IMPORT_CSV\temp_dataAPI.csv"
			dbms = csv replace;
		run;
	/*	Concatenate the 2 together (MASTER csv file)*/
		data _null_;
			file &file. mod lrecl=1073741823;
			infile "&dir.\API_IMPORT_CSV\temp_dataAPI.csv" ls=32767;
			input x : $32767.;
			put _infile_;
		run;
%mend masterCSV;
*%masterCSV(data=mydata, file=incsv, overwriteBehavior=normal, returnContent=count, token=TEST);

*------------------------------------------------------------------------------
* MACRO: Calculates filesize of an external file (used to get kB amount of the
* 			MASTER CSV file)
*------------------------------------------------------------------------------;
%macro filesize(file);
	%global kb;
	%local fid Bytes;
		%let fid=%sysfunc(fopen(&file.));
		%let Bytes=%sysfunc(finfo(&fid.,File Size (bytes)));
		%let kb = %sysevalf(&Bytes. / 1024);
		 %put NOTE: File size of &file. is &kb. kilobytes;
		%let fid=%sysfunc(fclose(&fid.));
%mend filesize; 

*-------------------------------------------------------------------------------
* MACRO: Store number of observations within the master dataset
*-------------------------------------------------------------------------------;
%macro nobs(ds);
	%global nobs;
	 %let dsid=%sysfunc(open(&ds.,in));
	 %let nobs=%sysfunc(attrn(&dsid,nobs));
	 %let rc=%sysfunc(close(&dsid));
%mend;

*-------------------------------------------------------------------------------
* MACRO: Calculates the ratio of kiloBytes per total observations (i.e. the ratio
*			of the MASTER CSV external file kBs to the total number of observations
*			in the main dataset). Next calculate how many observations are needed to
*			be under a specific file size (i.e. 400kB) using the kb/obs ratio and
*			calculate how many datasets need to be created in order to split up the
*			main dataset into smaller datasets which are under the specific kB amount.
*-------------------------------------------------------------------------------;
%macro calc_CSV(fsize_kB=, data=);
	%global datanumb obs_goal;
	%local size R;
		%filesize(in);
		%nobs(&data.);
		%if %sysfunc(ceil(&kb.)) > &fsize_kB. %then
			%do;
				%let R = %sysevalf(&kb./&nobs.);
				%let obs_goal = %eval(%sysfunc(ceil(&fsize_kB./&R.)));
				%let datanumb = %eval(%sysfunc(ceil(&nobs./&obs_goal.)));
			%end;
		%else
			%do;
				%let obs_goal = &nobs.;
				%let datanumb = 1;
			%end;
%mend calc_CSV;

*-------------------------------------------------------------------------------
* Build CSV files separately
*-------------------------------------------------------------------------------;
%macro buildcsv (data=, records=);
	%let k = 0;
	%do i = 1 %TO &nobs. %by &records. ;
			%let k = %eval(&k+1);
					proc export data=&data (firstobs=&i obs=%eval(&i. +&records. -1))
						outfile = "&dir.\API_IMPORT_CSV\temp_in%eval(&i.-1).csv"
					dbms = csv replace;
			run;
	%end;
%mend buildcsv;

*-------------------------------------------------------------------------------
* MACRO -- API IMPORTER::Sends SAS API-ready files to REDCap in smaller sets. First,
			  filename statements assign output files. Second, create the CSV formatted
			  API file for the trimmed down dataset (Under 500kB). Concatenate the API
			  parameter row on top of the smaller dataset. Execute proc http and send 
			  the data to REDCap. Loop through this until all datasets have been sent
			  to REDCap.
*-------------------------------------------------------------------------------;
%macro API_CSV(overwriteBehavior=, returnContent=, token=);
	%do j = 1 %to &datanumb.;
	/*Assign filename statements*/
		filename in&j. "&dir.\API_IMPORT_CSV\in&j..csv";
		filename out&j. "&dir.\API_IMPORT_CSV\out&j..csv";
		filename stat&j. "&dir.\API_IMPORT_CSV\status&j..txt";

	/*	Create API Parameter row*/
		data _NULL_;
			file in&j. lrecl=1073741823;
			put "%NRStr(content=record&format=csv&type=flat&returnformat=csv&returnContent=)&returnContent.%NRStr(&overwriteBehavior=)&overwriteBehavior.%NRStr(&)token=&token.%NRStr(&)data=";
		run;

	/*	Concatenate the 2 together*/
		data _NULL_;
			file in&j. mod lrecl=1073741823;
			infile "&dir.\API_IMPORT_CSV\temp_in%eval(&j.*&obs_goal. - &obs_goal).csv" ls=32767;
			input x : $32767.;
			put _infile_;
		run;
	/*Execute the http procedure using the 'post' method*/
		proc http
			in=in&j.
			out=out&j.
			headerout = stat&j.
			url=&url.
			method='post';
		run;

	/* Delete all temporary csv files created utilizing the x-command which accesses MS-DOS commands*/
		options noxsync noxwait noxmin;
		x "erase &dir.\API_IMPORT_CSV\temp_in%eval(&j.*&obs_goal. - &obs_goal).csv";
		x "erase &dir.\API_IMPORT_CSV\temp_dataAPI.csv";	
	%end;
%mend API_CSV;

*-------------------------------------------------------------------------------
* PRIMARY MACRO: Combine all macros from above and access the API (DATA IMPORT TO REDCap)
*-------------------------------------------------------------------------------;
%macro CSVIMPORT(data=, dir=, token=, url=, filesize=400, overwriteBehavior=normal, returnContent=count);
	/*	1--Check for empty dataset, if empty then escape macro*/
			proc sql noprint;
	 			select count(*) into :obs from &data.;
			quit;
			%if %eval(&obs. = 0) %then 
				%do;
					%PUT WARNING: Dataset "&data." has 0 records. CSV format: CSVIMPORT MACRO, MACRO has aborted operation.;
					%GOTO exit;
				%end;
	/* 2--SET options and create directory*/
			options missing = "" dlcreatedir;
			libname na "&dir.\API_IMPORT_CSV";
			filename in  "&dir.\API_IMPORT_CSV\MASTER_IMPORT_IN_CSV.csv";
			%let url   = "&url.";
	/*	3--Write the MASTER CSV file*/
			%masterCSV(data=&data., file=in, overwriteBehavior=&overwriteBehavior., returnContent=&returnContent., token=&token.);
	/*	4--Calculate MASTER CSV filesize and how many individual datasets I need to create
			 to be under the specified kB size*/
			%calc_CSV(fsize_kB=&filesize.);
	/*	5--From the calculations above, split the MASTER dataset into equal/balanced datasets*/
			%buildcsv (data=&data., records=&obs_goal.);
	/*	6--Create individual CSV files for each dataset and send it to REDCap utilizing the API*/
			%API_CSV(overwriteBehavior=&overwriteBehavior., returnContent=&returnContent., token=&token.);
			options missing = . nodlcreatedir;
%exit: %mend CSVIMPORT;


/*EXAMPLE MACRO CALL

%CSVIMPORT(data=mydata, dir=\\serverABC\REDCAP_TESTING\CSV, 
				token=REDCAP_API_TOKEN, url=Your_REDCap_URL); 

	::Defaults
		- filesize of 400kb set
		- overwrite behavior is normal
		- return content is a count
*/


*end REDCap_API_Importer_CSV.sas;


/*FOR MORE INFORMATION*/

*Refer to your REDCap API help page OR review this external document about REDCap API from The University 
of Chicago. 'http://cri.uchicago.edu/redcap/wp-content/uploads/2013/05/REDCap-API.pdf'

Hopefully this can make your future data imports automated and much more efficient!

Best Regards,,
Randy B.
;

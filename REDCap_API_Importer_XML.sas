/******************************************************************************
PROGRAM NAME:   REDCap_API_Importer_XML.sas

PRIMARY MACRO:	 XMLIMPORT(data=, dir=, token=, url=, filesize=, overwriteBehavior=, returnContent=)

SAS Version:	 9.3

REDCap Version: 5.0.15

PURPOSE:			 MACRO: Read a SAS dataset and import it into REDCap using CSV formatting

INPUT FILES:	 SAS dataset of choice which is ready to be imported into REDCap

OUTPUT FILES:	 &dir.\API_IMPORT_CSV\in.csv, &dir.\API_IMPORT_CSV\out.csv, &dir.\API_IMPORT_CSV\status.txt

AUTHOR:			 Randy Burnham
TITLE:			 Statistical Research Specialist

ORGANIZATION:	 Rocky Mountain Poison and Drug Center, Denver, CO

DATE CREATED:   04/11/2014
*******************************************************************************/

*-------------------------------------------------------------------------------
* API IMPORTER (XML version):::Name of Primary MACRO: 'XMLIMPORT'
*-------------------------------------------------------------------------------;
**XMLIMPORT MACRO Parameters
	REQUIRED:
		data					 = "REDCap ready" SAS dataset (must be in exact formatting as in REDCap database)
		dir					 = Unquoted filepath to the directory that you want the API import information dumped into
		token					 = User and Project specific token acquired from your REDCap project
		url					 = REDCap specific URL for your site

	OPTIONAL:
		filesize				 = filesize you would like to limit for the 'XML in file' imported into REDCap
		overwriteBehavior	 = API parameter for overwrite behavior in REDCap (values=normal | overwrite)
		returnContent  	 = Specify what REDCap should return in the "out" files (values=count | ids | nothing)

**NOTES on Importing with the REDCap API:
	- REDCap data that contain leading zero values pose issues with API importing. In order to resolve this,
	  re-format the variables in the SAS dataset to contain leading zero values (i.e. a format of z2.). One
	  could also edit the REDCap format of the variables to not have leading zero values.
	- Data containing "<", ">", "&", OR "+" values may have issues with API importing.
		- Specifically, 
			- "<" and ">" have issues with XML importing and throws a server error when read in
			- "&" stops the API import process (this is believed to be a proc http issue)
			- "+" does not appear in data when using the API, instead blank values are inserted

		***TO RESOLVE THESE ISSUES: WRAP your data with ![CDATA[any data value]]
			-All data within the CDATA brackets will be ignored by the parser when SAS is talking to REDCap throuh
				the API. This can be implemented right here in the macro within the 'writexml' macro below.

	- Filesize issues arise when an "in" file exceeds 500kb, split the data up to be under this amount prior
	  to importing. Feel free to mess around with the filesize, to see what is most efficient. I found for this
	  XML version, 440kb was among the quickest (however this can vary dependent on your server setup).
	- Missing values need to be changed to "" rather than '.'. This MACRO handles this for you.
	- If permanent formats are created within datasteps, make sure the dataset being sent to REDCap
	  is the data that REDCap expects. Strip new formats that were created and make sure all date variables within
	  your dataset have the format "YYMMDD.". REDCap is picky on what data it takes (this is a good thing).
	- Also make sure within REDCap the API abilities and 'Create Records' permissions are turned on, otherwise
	  you will get a 403 error when executing the macro.
*-------------------------------------------------------------------------------;

*-------------------------------------------------------------------------------
* MACRO: Creates macro variables for each variable name in the master dataset. 
*			This macro also gets a count of how many observations and variables
*			are in the master dataset. These vars will be used in the %writexml
*			macro for the XML file creation. The total obs "N" variable will be
*			used for later calculations.
*-------------------------------------------------------------------------------;
%macro getvars(data);
	proc contents data=&data out=pc noprint; run;
	proc sort data=pc; by varnum; run;
%global N lastobs nvar;
	data _null_;
		set sashelp.vtable (where=(libname='WORK' and memname=upcase("&data")));
		call symputx('nvar',nvar);
	run;
		%macro varglob;
			%do k=1 %to &nvar.;
				%global var&k.;
			%end;
		%mend varglob;
		%varglob;
	data _NULL_; set pc end=eof nobs=nobs;
		if _N_ = 1 then
				call symputx('N', nobs);
		call symputx('var'||strip(varnum), NAME);
		if eof then
			call symputx('lastobs', _N_);
	run;
%mend getvars;

*-------------------------------------------------------------------------------
* MACRO: Writes the XML format with separate put statements to save LRECL space
	-Input the ![CDATA[]] here to account for special characters in the data.
*-------------------------------------------------------------------------------;
%macro writexml;
	put "<item>" @;
	%do i= 1 %to &lastobs.;
		put "<&&var&i.>" @;
			put &&var&i. +(-1) @;
		put "</&&var&i.>" @;
	%end;
	put "</item>" @;
%mend writexml;

*-------------------------------------------------------------------------------
* MACRO: Creates REDCap XML formatted API parameter file
*-------------------------------------------------------------------------------;
%macro redcapIN(data=, file=, overwriteBehavior=normal, returnContent=count);
data _NULL_; set &data. end=eof;
	file &file. lrecl=32767;
	if _N_ = 1 then /*Write only once*/
		do;
			put "token=&token." @;
			put "%NRStr(&)content=record" @;
			put "%NRStr(&)format=xml" @;
			put "%NRStr(&)type=flat" @;
			put "%NRStr(&)returnformat=xml" @;
			put "%NRStr(&)returnContent=&returnContent." @;
			put "%NRStr(&)overwriteBehavior=&overwriteBehavior." @;
			put "%NRStr(&)data=<?xml version='1.0' encoding='UTF-8' ?><records>" @;
		end;

	%writexml;

	if eof then
		put "</records>";
run;
%mend redcapIN;

*------------------------------------------------------------------------------
* MACRO: Calculates filesize of an external file (used to get kB amount of the
* 			MASTER XML file)
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
* MACRO: Calculates the ratio of kiloBytes per total observations (i.e. the ratio
*			of the MASTER XML external file kBs to the total number of observations
*			in the main dataset). Next calculate how many observations are needed to
*			be under a specific file size (i.e. 400kB) using the kb/obs ratio and
*			calculate how many datasets need to be created in order to split up the
*			main dataset into smaller datasets which are under the specific kB amount.
*-------------------------------------------------------------------------------;
%macro calc(fsize_kB);
	%global datanumb;
	%local size R obs_goal;
		%filesize(in);
		%if %sysfunc(ceil(&kb.)) > &fsize_kB. %then
			%do;
				%let R = %sysevalf(&kb./&N.);
				%let obs_goal = %eval(%sysfunc(ceil(&fsize_kB./&R.)));
				%let datanumb = %eval(%sysfunc(ceil(&N./&obs_goal.)));
			%end;
		%else
			%let datanumb = 1;
%mend calc;

*-------------------------------------------------------------------------------
* MACRO: Split the datasets up according to the resolved datanumb value from %calc
*			SPLIT MACRO FROM: http://www2.sas.com/proceedings/sugi27/p083-27.pdf
*-------------------------------------------------------------------------------;
%macro split(ndsn=&datanumb., data=);
	data %do i = 1 %to &ndsn.; dsn&i. %end; ;
		retain x;
		set &data nobs=nobs;
		if _N_ = 1 then
			do;
				if mod(nobs,&ndsn.) eq 0
					then x=int(nobs/&ndsn.);
				else x=int(nobs/&ndsn.)+1;
			end;
		if _N_ le x then output dsn1;
			%do i = 2 %to &ndsn.;
				else if _N_ le (&i.*x)
				then output dsn&i.;
			%end;
		drop x;
	run;
%mend split;

*-------------------------------------------------------------------------------
* MACRO: API IMPORTER::Sends XML API-ready files to REDCap in smaller sets. First,
			filename statements assign output files. Second, create the XML formatted
			API file for the trimmed down dataset (Under 500kB). Execute proc http
			and send the data to REDCap. Loop through this until all datasets have
			been sent to REDCap.
*-------------------------------------------------------------------------------;
%macro API_XML;
	%do j = 1 %to &datanumb.;
		filename in&j. "&dir.\API_IMPORT_XML\in&j..xml";
		filename out&j. "&dir.\API_IMPORT_XML\out&j..xml";
		filename stat&j. "&dir.\API_IMPORT_XML\status&j..txt";
		%redcapIN(file=in&j., data=dsn&j.);

		proc http
			in=in&j.
			out=out&j.
			headerout = stat&j.
			url=&url.
			method='post';
		run;
	%end;
%mend API_XML;

*-------------------------------------------------------------------------------
* PRIMARY MACRO: Combine all macros from above and access the API (DATA IMPORT TO REDCap)
*-------------------------------------------------------------------------------;
%macro XMLIMPORT(data=, dir=, token=, url=, filesize=440, overwriteBehavior=normal, returnContent=count); /*Default filesize of 440*/
	/*	1--Check for empty dataset, if empty then escape macro*/
		proc sql noprint;
 				select count(*) into :obs from &data.;
			quit;
			%if %eval(&obs. = 0) %then 
				%do;
					%PUT WARNING: Dataset "&data." has 0 records. XML format: XMLIMPORT MACRO has aborted operation.;
					%GOTO exit;
				%end;
		options missing = "" dlcreatedir;
		libname na "&dir.\API_IMPORT_XML";
		%global url;
		%let url   = "&url.";
		filename in  "&dir.\API_IMPORT_XML\MASTER_IMPORT_IN_XML.xml";
	/*	2--Get variables for future xml file writing*/
		%getvars(&data);
	/*	3--Write the MASTER XML file*/
		%redcapIN(data=&data, file=in, overwriteBehavior=&overwriteBehavior, returnContent=&returnContent);
	/*	4--Calculate MASTER XML filesize and how many individual datasets I need to create
			 to be under the specified kB size*/
		%calc(fsize_kB=&filesize);
	/*	5--From the calculations above, split the MASTER dataset into equal/balanced datasets*/
		%split(data=&data);
	/*	6--Create individual XML files for each dataset and send it to REDCap utilizing the API*/
		%API_XML;
		options missing = . nodlcreatedir;
%exit: %mend XMLIMPORT;

/*EXAMPLE MACRO CALL

%XMLIMPORT(data=mydata, dir=\\serverABC\REDCap_TESTING\XML,
				token=REDCap_API_Token, url=Your_REDCap_URL);
*FILESIZE of 440 was tested to be the fastest filesize for importing (Could vary depending on your setup);

	::Defaults
		- filesize of 400kb set
		- overwrite behavior is normal
		- return content is a count
*/

*end REDCap_API_Importer_XML.sas;


/*FOR MORE INFORMATION*/

*Refer to your REDCap API help page OR review this external document about REDCap API from The University 
of Chicago. 'http://cri.uchicago.edu/redcap/wp-content/uploads/2013/05/REDCap-API.pdf'

Hopefully this can make your future data imports automated and much more efficient!

Best Regards,,
Randy B.
;

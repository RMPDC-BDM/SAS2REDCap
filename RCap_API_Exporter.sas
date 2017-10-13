/******************************************************************************
PROGRAM NAME:  RCap_API_Exporter.sas

SAS Version:	9.3/9.4

PURPOSE:		Export REDCap data to a directory as specified to SAS datasets in an
				automated fashion using information provided from the data
				dictionary/metadata from REDCap.

INPUT FILES:  	pathnames.sas

OUTPUT FILES:

AUTHOR:			RIB
DATE CREATED:	26FEB2016

VALIDATED BY:	JL
DATE VALIDATED: 09MAY2016

MODIFIED BY:	RIB
DATE MODIFIED:	13MAY2016
MODIFICATIONS:	Adjusted code to account for special style characters in the metadata.
					 Also made adjustment to form name capture for non-longitudinal projects 

VALIDATED BY:	JL
DATE VALIDATED: 13MAY2016

MODIFIED BY:	RIB
DATE MODIFIED:	24MAY2016
MODIFICATIONS:	2nd attempt to adjust code to account for special style characters in the metadata.
					Used PERL regular expressions to strip out the HTML tags from a SAS website code reference

VALIDATED BY:	AGT
DATE VALIDATED: 24MAY2016

MODIFIED BY:	RIB
DATE MODIFIED:	27AUG2016
MODIFICATIONS:	Removed single quotes around start values for final format library output
					Character values were not being formatted properly, however numerics were fine. The character data values
					were being wrapped in single quotes within the data which caused issues.

VALIDATED BY:	SKN
DATE VALIDATED:	30Aug2016
*******************************************************************************/

*-------------------------------------------------------------------------------
* Filename MACRO
*-------------------------------------------------------------------------------;
	%macro filename(content);
		filename in  "&dir.\Parameter_Files\in_&content..csv";
		filename out "&dir.\Raw_Data\out_&content._delete_me.csv";
		filename out_new "&dir.\Raw_Data\out_&content..csv";
	%mend filename;

*-------------------------------------------------------------------------------
* IN File Creation MACRO (SIMPLE CONTENT CHANGE)
*-------------------------------------------------------------------------------;
	%macro in_params(content);
		data _null_ ;
			file in lrecl=1073741823;
			put "%NRStr(content=)&content.%NRStr(&type=flat&format=csv&token=)&token.%NRStr(&)";
		run;
	%mend in_params;

*-------------------------------------------------------------------------------
* Proc HTTP MACRO
*-------------------------------------------------------------------------------;
	%macro http;
		proc http
			in=in
			out=out
			url=&url
			method='post';
		run;

		data _null_ ;
		  if eof then put 'NOTE: Records read=' newn 'Records with missing quotes=' missq ;
		  infile out lrecl=32767 end=eof ;
		  file out_new lrecl=32767;
		  nq=0;
		  do until (mod(nq,2)=0 or eof );
			  input;
			 _INFILE_ = TRANSLATE(_INFILE_,' ' ,'0D'x);
			  newn+1;
			  nq = nq + countc(_infile_,'"');
			  put _infile_ @;
			  if mod(nq,2) then do;
				 missq+1;
				 put ' ' @;
			  end;
		  end;
		  put;
		run;
	%mend http;

*-------------------------------------------------------------------------------
* Proc IMPORT MACRO
*-------------------------------------------------------------------------------;
	%macro import(content, guess=);
		proc import
			datafile="&dir.\Raw_Data\out_&content..csv"
			out=&content.
			dbms=csv
			replace;
			guessingrows=&guess.;
		run;
	%mend import;

*-------------------------------------------------------------------------------
* Simple CONTENT EXPORT MACRO
*-------------------------------------------------------------------------------;
	%macro export_content(content, custom_import=0, guess=250);
	%local custom_import;
		%filename(&content.);
		%in_params(&content.);
		%http;
		%if &custom_import. ^= 1 %then
			%do;
				%import(&content., guess=&guess.);
			%end;
		systask command "DEL ""&dir.\Raw_Data\out_&content._delete_me.csv""";
	%mend export_content;









*-------------------------------------------------------------------------------
* API EXPORT MACRO BEGINS:
*-------------------------------------------------------------------------------;
***STEPS:
	1. Export Metadata
	2. Parse Metadata and create a dataset of formats, write formats, and save dataset for variable attributes.
	3. Is the project longitudinal or not?
	4. Grab the identifier for the REDCap project and store it in a macro variable
	5. If longitudinal (if no skip this step)
		a. Pull the event form mapping information to get the data structure (needed for api call and data structure)
		b. Create the proper API call for each form
		c. Output raw csv file from REDCap
	6. If NOT longitudinal (if longitudinal skip this step)
		a. Pull the export field names to parse and extract the 'form' names (needed for api call and data structure)
		b. Create the proper API call and pull out each form
		c. Output raw csv file from REDCap
	7. Import raw csv files based on form name output from the API calls.
		a. Import utilizes metadata to understand variable attributes, type, formats, informats, etc..
;

%macro REDCapToSAS(token, dir);

libname dir "&dir.";
%let url   = "YOUR REDCap URL.edu/api/";

*-------------------------------------------------------------------------------
* Create Directory Folders for Dumping Files
*-------------------------------------------------------------------------------;
	option dlcreatedir;
	libname rawdata "&dir.\Raw_Data";
	libname na2 "&dir.\Parameter_Files";
	option nodlcreatedir;
*-------------------------------------------------------------------------------
* METADATA EXPORT
*-------------------------------------------------------------------------------;
	%export_content(metadata, custom_import=1);

		data metadata;
			infile "&dir.\Raw_Data\out_metadata.csv" dlm = ',' MISSOVER DSD lrecl=32767 firstobs=2;
			input field_name:$100./*$31.*/ form_name:$250. tmp $ field_type:$250. field_label:$2500. select_choices_or_calculations:$5000. tmp3 $ datefieldtype:$100.;
			order+1;
			if not missing(datefieldtype) then field_type = datefieldtype;
			drop tmp: datefieldtype;
			if missing(form_name) or missing(field_type) or field_type='descriptive' then delete;
			if field_type='email' then field_label = 'Email Address';
		run;

	/*Process Metadata (separate program written, pasted here for the sake of the macro) input data = 'metadata' output data = 'formats'*/
	/*		%include "&dir.\DM01_Metadata_Format_Creation.sas";*/

				/*What is the max number of selections within the data dictionary? I need to count the '|' values*/
				data pipe_count;
					set metadata;
					pipe_numb = countc(select_choices_or_calculations, '|');
				run;
				proc means data=pipe_count noprint;
					var pipe_numb;
					output out=pipe_numb_max(drop=_:) max=maxpipe;
				run;

				data _null_;
					set pipe_numb_max;
					call symputx('maxpipe', maxpipe+1);
				run; %put &maxpipe.;

				/*Split out the metadata checkbox selections (array within array here)*/
				data metadata_splitout;
					set metadata;
					length field1 - field&maxpipe. formata1 - formata&maxpipe. formatb1 - formatb&maxpipe. $500.;
					array x{*} $ field1 - field&maxpipe.;
					array y{*} $ formata1 - formata&maxpipe.;
					array z{*} $ formatb1 - formatb&maxpipe.;

					if field_type in('radio', 'checkbox', 'dropdown') then
						do i = 1 to &maxpipe.;
							x(i) = scan(select_choices_or_calculations, i, '|');

							y(i) = scan(x(i), 1, ',');
							z(i) = strip(tranwrd(x(i), scan(x(i), 1, ',')||',', ''));/*This line grabs everything but the 1st scanned word (helps capture labels with commas in them)*/
						end;

					drop i;
				run;

				data formatted_fields; 
					set metadata_splitout;
					array start_a{*} formata1 - formata&maxpipe.;
					array label_a{*} formatb1 - formatb&maxpipe.;
					do i = 1 to &maxpipe.;
						start = strip(start_a(i));
						label = strip(label_a(i));
						if missing(start) then delete;
						if field_type = 'checkbox' then chbox_order = i;

						output;
					end;
					keep order field_name field_type field_label form_name start label chbox_order;
				run;

				proc sort data=metadata;
				   by field_name field_type;
				run;
				/*Handle other field types*/
				data other_fields;
					set metadata;
					by field_name field_type;
					if field_type not in('radio', 'checkbox', 'dropdown') and first.field_type = 1 then output;
				run;

				/*Slap the text fields and fields with different formats together*/
				data formats_a;
					set formatted_fields other_fields(keep=order field_name field_label field_type form_name);

					/*Account for the checkbox field name variable values*/
					variable = field_name;
					if field_type = 'checkbox' then
						variable = strip(field_name) || '___' || strip(start);
				run;

				proc sort data=formats_a(keep=form_name order) out=form_names_tmp;
				   by form_name descending order;
				run;
				proc sort data=form_names_tmp nodupkey;
				   by form_name;
				run;
				data form_names; set form_names_tmp;
					by form_name order;
					length variable $100./*$31.*/ field_type $250.;
						variable = strip(form_name) || '_complete';
						type = 'n';
						field_type = 'form_complete';
						field_label = 'Complete?';
						order=order+0.5;
				run;

				data format_ready; 
					set formats_a form_names;
					if label ^='' and field_type in('checkbox') then
						field_label = strip(field_label)||' (choice='||strip(label)||')';
				run;

				proc sort data=format_ready;
				   by order;
				run;
				data format_ready_final;
					set format_ready;
					variable_clean = variable;
						if length(variable) >=31 then /*31 is the redcap length that is used to allow for '_' in format names (i.e. 32 total)*/
							do;
								vnum+1;/*This will ensure unique assignment values*/
								variable_clean = substr(variable, 1, 20) || '_v_' || left(vnum - 1);
							end;
						drop variable vnum;
						rename variable_clean = variable;
				run;


			*-------------------------------------------------------------------------------
			* Create Formats
			*-------------------------------------------------------------------------------;

				*Prepare imported dataset for the format procedure;
				data formats; set format_ready_final;

				/*RB Edit for HTML Tags: PERL REGULAR EXPRESSION SEARCH is much better 24MAY2016*/
					/*http://support.sas.com/techsup/notes/v8/24/717.html*/
					  /*before = field_label;*/
					  reg_ex = prxparse("s/<.*?>//");
					  call prxchange(reg_ex,99,field_label); /*removes up to 99 html tags*/
				/*End RB Edit 24MAY2016*/

  				/*RB Added Code 13MAY2016*/
					/*	length new_label $2500.;*/
						/*	if index(field_label, 'style=')>0 then */
						/*		new_label = strip(scan(field_label, -1, '>'));*/
						/*		else new_label = strip(field_label);*/
						/*	drop field_label;*/
						/*	rename new_label = field_label;*/
				/*End RB Added Code 13MAY2016*/

				field_label = compress(field_label, "'");/*RC output labels don't use single quotes*/
					if field_type = 'form_complete' then
						do;
							fmtname = strip(variable) || '_';
							start=0; label='Incomplete';
							output;
							start=1; label='Unverified';
							output;
							start=2; label='Complete';
						end;
					fmtname = strip(variable) || '_';
					if (start ^='' AND (anyalpha(start) = 0 and anypunct(start) = 0))/*No letters or punctuation, then assign as numeric*/
						OR
						field_type in('form_complete' 'number' 'integer' 'zipcode' 'calc' 'slider')
							then type='n';
						else type='c';

					

					/*Checkbox values are only 0 or 1 rather than what the metadata says (i.e. RACE 3=Asian is actually Race___3 = 1 for Asian NOT 3)*/
					if field_type = 'checkbox' then
						start = '1'; /*forces all start values to be 1*/
					OUTPUT;

					if field_type = 'checkbox' then
						do;
							start = '0';
							label = '';
							output;
						end;
					drop reg_ex;/*RB added 24MAY2016*/
				run;

				proc sort data=formats(where=(start^='')) out=formats_for_output_s 
								nodupkey sortseq=linguistic (numeric_collation=ON);
					by variable start label;
				run;

*-------------------------------------------------------------------------------
* PROJECT INFO EXPORT (Useful for longitudinal status)
*-------------------------------------------------------------------------------;

				%export_content(project);
					data _null_;
						set project;
						call symputx('longitudinal', is_longitudinal);
						call symputx('project_title', project_title);
					run;%put &=longitudinal;

				%if &longitudinal. = 1 %then
					%do;
					/*Events*/
						%export_content(event); /*Use this for REDCap Event Name Format*/
						data event_formats;
							set event(rename=(event_name=label unique_event_name=start)
										 keep=event_name unique_event_name);
							fmtname = 'REDCAP_EVENT_NAME_';
							type='c';
						run;
					%end;

				data formats_for_output;
					set formats_for_output_s %if &longitudinal. = 1 %then
					%do; event_formats %end;;
/*RB Edit 27AUG2016*/
/*					length start_new $500.;*/
/*					if type='c' then start_new = quote(strip(start), "'");*/
/*						else start_new = start;*/
/*					drop start;*/
/*					rename start_new = start;*/
				run;

			*Create format from the dataset imported;
				proc format cntlin=formats_for_output 
							  library=dir.rc_export_format_file
								cntlout=dir.rc_export_format_dataset;
				run;

		options fmtsearch=(dir.rc_export_format_file);
*-------------------------------------------------------------------------------
* Formats and Variable structure has been created, now I can move on.
*-------------------------------------------------------------------------------;


*-------------------------------------------------------------------------------
* FIELD NAME EXPORT (Useful for grabbing form complete variables and checkbox variables)
*-------------------------------------------------------------------------------;
	%export_content(exportFieldNames, guess=5000);
	data _null_;
		set exportFieldNames;
		if _N_=1 then
			call symputx('identifier', export_field_name);
	run;%put &=identifier;
	data _null_;
		set formats;*metadata; /*RB edited 13MAY2016: used cleaned formats dataset rather than metadata for proper field label*/
		if field_name="&identifier." then
			call symputx('id_label', field_label);
	run; %put &=id_label;

*-------------------------------------------------------------------------------
* Longitudinal Checks
*-------------------------------------------------------------------------------;

/*	%macro forms_events;*/
		%if &longitudinal. = 1 %then
			%do;
			/*Arms*/
				/*%export_content(arm); NOT NECESSARY (no parameter for arm specific export)*/
			/*Events*/
				%export_content(event); /*Use this for REDCap Event Name Format*/
				data event_formats;
					set event(rename=(event_name=label unique_event_name=start)
								 keep=event_name unique_event_name);
					fmtname = 'REDCAP_EVENT_NAME_';
					type='c';
				run;
				/*Creates redcap event name format*/
				proc format cntlin=event_formats;
				run;
			/*Form Event Mapping*/
				%export_content(formEventMapping, custom_import=1);
						data formEventMapping;
							infile "&dir.\Raw_Data\out_formEventMapping.csv" dlm = ',' MISSOVER DSD lrecl=32767 firstobs=2 ;
							input arm_num unique_event_name:$250. form_name:$250.;
						run;
					proc sort data=formEventMapping;
						by form_name;
					run;
					proc sort data=metadata(keep=form_name) out=m_sort nodupkey;
						by form_name;
					run;
					data formEventMapping_clean;
						merge formEventMapping(in=a) m_sort(in=b);
						by form_name;
						if a and b;
					run;

				/*Longitudinal ONLY*/
					proc sort data=formEventMapping_clean sortseq=linguistic (numeric_collation=on);
						by form_name unique_event_name;
					run;
					proc transpose data=formEventMapping_clean out=formEvents_t(drop=_NAME_) prefix=event;
						by form_name;
						var unique_event_name;
					run;
					proc contents data=formEvents_t out=pc(where=(NAME ^in('_NAME_' 'form_name'))) noprint; run;
					%let event_num = &sysnobs.;

					data events;
						set formEvents_t;
						length events $10000;
						events = catx(',', of event1-event&event_num.);
						drop event1-event&event_num.;
					run;

					data _null_;
						set events end=eof;
						/*Create macro variables for specific event and form combinations dependent on event form amounts calculated*/
							do;
								call symputx('form' || left(_N_), form_name, 'g');
								call symputx('event'|| left(_N_), events, 'g');
							end;

						/*Calculate the max number of multi form event combinations (for the do loop to follow)*/
							if eof then
									call symputx('max_formevents', left(_N_), 'g');
					run; /*%put _USER_;*/
			%end;
		%else
			%do;
				data tmp;*_null_;
					set exportFieldNames end=eof;
					x = length(export_field_name);
					if x > 8 /*RB edited 13MAY2016 code to properly grab form names (survey_completer was being grabbed when it shouldn't for MAPS PC SURVEY testing)*/
						and substr(export_field_name, x-8) = '_complete' then
					/*if index(export_field_name,'_complete') > 0 then*/
						do;
							flag+1;
							call symputx('form'||left(flag), substr(export_field_name, 1, x-9), 'g');
							form_name_check = substr(export_field_name, 1, x-9);
						end;
					if eof then call symputx('max_formevents', flag, 'g');
				run;/*%put &=form1 &=form2 &=form5 &=form7 &=form8 &=form9 &=max_formevents;*/
			%end;
/*	%mend forms_events;*/
/*	%forms_events;*/



*-------------------------------------------------------------------------------
* MACROS TO RUN RECORD EXPORT
*-------------------------------------------------------------------------------;
	proc datasets;
		delete summary;
	run;quit;
	/*MACRO for informat statement in datastep*/
	%macro var_informats;
		%do i = 1 %to &max_var.;
			&&var&i. &&informat&i.
		%end;
	%mend var_informats;

	/*MACRO for input statement in datastep*/
	%macro var_input;
		%do i = 1 %to &max_var.;
			&&var&i. &&input&i.
		%end;
	%mend var_input;

	/*MACRO for format statement in datastep*/
	%macro var_formats;
		%do i = 1 %to &max_var.;
				&&var&i. &&format&i.
		%end;
	%mend var_formats;

	/*MACRO for label statement in datastep*/
	%macro var_fieldlabels;
		%do i = 1 %to &max_var.;
			&&var&i. = "&&field_label&i."
		%end;
	%mend var_fieldlabels;

	/*MACRO Symbol Deletion Variables*/
	%macro symbols_for_deletion;
		%do i=1 %to &max_var.;
			var&i. input&i. informat&i. format&i.
		%end;
	%mend symbols_for_deletion;

	%macro data_input_import(form);
		%local form;
		proc sort data=formats(where=(form_name="&form." and variable ^="&identifier.") keep=order chbox_order form_name variable fmtname type field_label field_type start label)
					 out=formats_subset
					 nodupkey
					 sortseq=linguistic (numeric_collation=ON);/*IMPORTANT for variable ordering when reading data*/
			by order chbox_order;
		run;
		data _NULL_;
			set formats_subset end=eof;
			length informat input format $250.;
			if type = 'c' then
				do;
					informat = '$500.';
					input = '$';
					format = '$500.';
				end;
			else if type = 'n' then
				do;
					informat = 'best32.';
					input = '';
					format = 'best12.';
				end;


			/*SPECIAL HANDLING (OVERWRITE PREVIOUS CODE PURPOSELY)*/
			if type = 'c' and start ^= '' then
					format = '$'||strip(fmtname)||'.';

			if type = 'n' and start ^= '' then
					format = strip(fmtname)||'.';

			if field_type = 'notes' then
				do;
					informat = '$5000.';
					input = '$';
					format = '$5000.';
				end;

			if field_type in('email' 'phone') then
				do;
					informat = '$500.';
					input = '$';
					format = '$500.';
				end;

			if field_type in('time') then
				do;
					informat='time5.';
					format='time5.';
				end;

			if field_type in('date_ymd' 'date_mdy' 'date_dmy') then
				do;
					informat='yymmdd10.';
					format='yymmdd10.';
				end;
			if field_type in('datetime_ymd ' 'datetime_mdy' 'datetime_dmy'
								  'datetime_seconds_ymd' 'datetime_seconds_mdy' 'datetime_seconds_dmy') then
				do;
					informat='ymddttm19.';
					input = '$';
					format='datetime19.';
				end;

			call symputx('var'||left(_N_), variable, 'g');

			call symputx('informat'||left(_N_), informat, 'g');
			call symputx('input'||left(_N_), input, 'g');
			call symputx('format'||left(_N_), format, 'g');
			call symputx('field_label'||left(_N_), substr(compress(field_label, '"&'), 1, 256), 'g');

			if eof then call symputx('max_var', left(_N_), 'g');
		run;/*%put _USER_; %put &var30. &max_var.;*/

		/*Special code to shorten the form length to 32 or below for SAS dataset name length to work (incorporates rc_)*/
			%let length = %sysfunc(length(&form.));
				/*%put &=form &=length;*/
			%symdel dataname / NOWARN;
			%global dataname;
				%if &length. <= 29 %then
					%do;
						%let dataname = &form.;
					%end;
				%else %if &length. >29 %then
					%do;
						%let dataname = %sysfunc(substr(&form., 1, 29));
					%end;


			data rawdata.rc_&dataname.;
				infile "&dir.\Raw_Data\out_&form..csv" dlm = ',' MISSOVER DSD lrecl=32767 firstobs=2;
				%if &longitudinal.=1 %then
					%do;
						informat &identifier. $500. redcap_event_name $500. %var_informats;
						input &identifier. $ redcap_event_name $ %var_input;
						format &identifier. $500. redcap_event_name $REDCAP_EVENT_NAME_. %var_formats;
						label &identifier.="&id_label." redcap_event_name='Event Name' %var_fieldlabels;
					%end;
			/*NO REDCAP EVENT NAME*/
				%else
					%do;
						informat &identifier. $500. %var_informats;
						input &identifier. $ %var_input;
						format &identifier. $500. %var_formats;
						label &identifier.="&id_label." %var_fieldlabels;
					%end;

			run;
			%macro nobs(ds);
				 %global nobs;
				 %let dsid=%sysfunc(open(&ds.,in));
				 %let nobs=%sysfunc(attrn(&dsid,nobs));
				 %let rc=%sysfunc(close(&dsid));
			%mend;
			%nobs(rawdata.rc_&dataname.);
			data sum;
				length dataset $32.;
				label DataSet = 'Data Set' Total_N = 'TOTAL N';
				DataSet = "&dataname.";
				Total_N = &nobs.;
				output;
			run;
			proc append base=summary data=sum force;
			run;
			%symdel symbols_for_deletion / NOWARN;
	%mend data_input_import;

*-------------------------------------------------------------------------------
* RECORDS EXPORT
*-------------------------------------------------------------------------------;
	%macro export_data;
		option noquotelenmax;
			/*Event Forms EXPORT to CSV*/
			%do z=1 %to &max_formevents.;
				%filename(&&form&z.);
				data _null_;
					  file in lrecl=1000000;
						put "content=record" @;
						put "%NRStr(&)format=csv" @;
						put "%NRStr(&)type=flat" @;
						put "%NRStr(&)fields=&identifier." @;/*Need ID output (e.g. subjid, case_number)*/
						put "%NRStr(&)forms=&&form&z." @;/*Form Name Looped value*/
						%if &longitudinal.=1 %then
							%do;
								put "%NRStr(&)events=&&event&z." @;/*Event Name(s) Looped value*/
							%end;
						put "%NRStr(&)token=&token." @;
						put "%NRStr(&)";
				run;

				%http;

				/*BIG STEP HERE (macro written above)*/
				%data_input_import(&&form&z.);

				systask command "DEL ""&dir.\Raw_Data\*_delete_me.csv""";

			%end;

		proc datasets nolist;
			delete event events event_formats exportfieldnames formats formats_a formats_for_output formats_subset
					 formatted_fields format_ready format_ready_final formeventmapping formeventmapping_clean formevents_t
					 form_names form_names_tmp metadata metadata_splitout m_sort other_fields pc pipe_count pipe_numb_max 
					 project sum tmp;
		run;quit;

		proc print data=summary noobs label;
		run;

			%if "&syserrortext." ^= "" %then
				%put NOTE: Last ERROR Detected: &syserrortext.;
				%else %if "&syserrortext." = "" %then
					%do;
						%put NOTE: NO ERRORS DETECTED BY MACRO;
						%put NOTE: Successful REDCap Export of "&project_title.";
					%end;
		option quotelenmax;
	%mend export_data;

	%export_data;

%mend REDCapToSAS;

*end of  RCap_API_Exporter.sas;

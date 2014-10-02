SAS2REDCap
==========

SAS Macros Utilizing the REDCap API for Data Exchange

PRIMARY MACRO:	SAS2REDCap

SAS Version:	9.3

REDCap Version: 5.0.15

PURPOSE:	MACRO: Read a SAS dataset and import it into REDCap using CSV or XML formatting

INPUT FILES:	SAS dataset of choice which is ready to be imported into REDCap

OUTPUT FILES:	&dir.\API_IMPORT_CSV\in.csv, &dir.\API_IMPORT_CSV\out.csv, &dir.\API_IMPORT_CSV\status.txt

AUTHOR:		Randy Burnham
	TITLE:	Statistical Research Specialist

CO-AUTHOR:	Jason Lones
	TITLE:	Clinical Data Manager | Data Storage Administrator | REDCap Administrator

ORGANIZATION:	Rocky Mountain Poison and Drug Center, Denver, CO

DATE CREATED:   04/12/2014

PLEASE READ:

3 MACROS:
   1. REDCap_API_Importer_CSV
   2. REDCap_API_Importer_XML
   3. REDCap_API_Importer_CSVandXML

You can utilize macros 1 and 2 on their own if you would like. However, the suggested macro to utilize is macro number 3. This macro gives you the flexibility to call either the csv or xml macro. To get the import macros up and running, save all of them to a specific directory on your computer. Within SAS use a %include statement to compile macro number 3 (as an example). Then input all of the necessary parameters for the macro in order to import a SAS dataset into REDCap. 

Make sure within your REDCap project:
   - You have API Import/Export turned on.
   - Also make sure to have 'CREATE RECORDS' checked within REDCap.


All parameters and known notes regarding REDcap data import are specified below.

-------------------------------------------------------------------------------
 API IMPORTER (CSV AND XML version)
-------------------------------------------------------------------------------;

MACRO Parameters
REQUIRED:

	data	="REDCap ready" SAS dataset (must be in exact formatting as in REDCap database)
	
	dir	=UNQUOTED filepath to the directory that you want the API import info dumped into
	
	token	=User and Project specific token acquired from REDCap
	
	url	=REDCap specific URL for your site

OPTIONAL:

	filesize =filesize you would like to limit for the 'XML infile' or 'CSV infile' imported into REDCap (<=500kb necessary)
	
	overwriteBehavior =API parameter for overwrite behavior in REDCap (values=normal | overwrite)
	
	returnContent =Specify what REDCap should return in the "out" files (values=count | ids | nothing)

NOTES on Importing Issues:

	- REDCap data that contain leading zero values pose issues with API importing. In order to resolve this,
	  re-format the variables in the SAS dataset to contain leading zero values (i.e. a format of z2.). One
	  could also edit the REDCap format of the variables to not have leading zero values.

	- Data containing "<" or ">" or "&" "+" values may have issues with API importing.
	
		Specifically, 

			- "<" and ">" have issues with XML importing and throws a server error when read in
			
			- "&" stops the API import process (SAS does this, not this program)
			
			- "+" does not appear in data when using the API, instead blank values are inserted (REDCap does this, 
			  not this program)

		TO RESOLVE THESE ISSUES for CSV:
		
			- Replace all '&' in the data with %26 (URL Encoded Character)
			
			- Replace all '+' in the data with %2B (URL Encoded Character)
			
			- The tags "<" and ">" should not be a problem with the CSV format.
			
		TO RESOLVE THESE ISSUES for XML: 
			
			- WRAP your data with ![CDATA[any data value]]
			
			- All data within the CDATA brackets will be ignored by the parser when SAS is talking to REDCap 
			  through the API. This can be implemented right here in the macro within the 'writexml' macro of
			  macro number 2.


	- Filesize issues arise when an "in" file exceeds 500kb, split the data up to be under this amount prior
	  to importing.

	- Very basic speed testing has been done with varying the format and filesize parameters. From the results, the XML
	  format is surprisingly twice as fast as the CSV format. Also, the optimal filesize is around 440kb.
	
	- If permanent formats are created within datasteps, make sure the dataset being sent to REDCap
	  is the data that REDCap expects. Strip new formats that were created and make sure all date variables within
	  your dataset have the format "YYMMDD.". REDCap is picky on what data it takes (this is a good thing).

	- Also make sure within REDCap the API abilities and 'Create Records' permissions are turned on, otherwise
	  you will get a 403 error when executing the macro.

-------------------------------------------------------------------------------;

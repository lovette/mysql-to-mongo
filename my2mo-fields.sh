#!/bin/bash

CMDPATH=$(readlink -f "$0")
CMDNAME=$(basename "$CMDPATH")
CMDDIR=$(dirname "$CMDPATH")
CMDARGS=$@

MY2MO_FIELDS_VER="1.0.1"

GETOPT_ORDERBY=0

##########################################################################
# Functions

# echo_stderr(string)
# Outputs message to stderr
function echo_stderr()
{
	echo $* 1>&2
}
    
# exit_arg_error(string)
# Outputs message to stderr and exits
function exit_arg_error()
{   
	local message="$1"

	[ -n "$message" ] && echo_stderr "$CMDNAME: $message"
	echo_stderr "Try '$CMDNAME --help' for more information."
	exit 1
}   
    
# exit_error(string)
# Outputs message to stderr and exits
function exit_error()
{   
	local message="$1"

	[ -n "$message" ] && echo_stderr "$CMDNAME: $message"
	exit 1
} 

# Print version and exit
function version()
{   
	echo "my2mo-fields $MY2MO_FIELDS_VER"
	echo
	echo "Copyright (C) 2011 Lance Lovette"
	echo "Licensed under the BSD License."
	echo "See the distribution file LICENSE.txt for the full license text."
	echo 
	echo "Written by Lance Lovette <https://github.com/lovette>"

	exit 0
}

# Print usage and exit 
function usage()
{   
	echo "Parses an SQL database schema file and creates an 'import.tables'"
	echo "file with a list of tables found, and a directory containing a file"
	echo "for each table listing the table columns/fields."
	echo "These files are then used by my2mo-export and my2mo-import"
	echo "to import data files into a MongoDB database."
	echo
	echo "Usage: my2mo-fields [OPTION]... OUTPUTDIR SCHEMAFILE"
	echo
	echo "Options:"
	echo "  OUTPUTDIR      Directory to write import.table and fields files"
	echo "  SCHEMAFILE     File containing SQL database schema"
	echo "  -h, --help     Show this help and exit"
	echo "  -o             Add table ORDER BY on PRIMARY KEY or first table field"
	echo "  -V, --version  Print version and exit"
	echo
	echo "Report bugs to <https://github.com/lovette/mysql-to-mongo/issues>"

	exit 0
}
 
function parse_schema()
{
	awk --re-interval -v OUTPUTDIR="$OUTPUTDIR" -v OPTORDERBY="$GETOPT_ORDERBY" '
	BEGIN {
		tablecount = 0;
		tablespath = sprintf("%s/import.tables", OUTPUTDIR, table);

		print "# List of tables to import" > tablespath;
		print "# TABLE [SELECT SQL]" >> tablespath;
	}

	{
		if ($1 == "CREATE" && $2 == "TABLE")
		{
			table = $3;

			gsub(/^[[:punct:]]{1}|[[:punct:]]{1}$/, "", table); # Trim quotes

			fieldcount = 0;
			fieldpath = sprintf("%s/fields/%s.fields", OUTPUTDIR, table);
			orderbyfield = "";

			print "# List of fields to import" > fieldpath;
			print "# COLUMN [SELECT SQL]" >> fieldpath;

			while (getline > 0)
			{
				field = $1;

				if (match(field, "^(\\)|KEY|PRIMARY|UNIQUE)$"))
				{
					if (field == "PRIMARY" && match($3, "^\\(([^\\)]+)", parts))
					{
						orderbyfield = parts[1];
						gsub(/^[[:punct:]]{1}|[[:punct:]]{1}$/, "", orderbyfield); # Trim quotes
						gsub(/[[:punct:]]{1},[[:punct:]]{1}/, ",", orderbyfield); # Remove imbedded quotes
						gsub(/,/, ", ", orderbyfield);
					}

					break;
				}

				gsub(/^[[:punct:]]{1}|[[:punct:]]{1}$/, "", field); # Trim quotes

				if (fieldcount == 0)
					orderbyfield = field;

				print field >> fieldpath;
				fieldcount++;

			}

			printf("...%-30s %2d fields\n", table, fieldcount);

			if (OPTORDERBY == 1)
				print table " ORDER BY " orderbyfield >> tablespath;
			else
				print table >> tablespath;

			tables[tablecount++] = table;
		}
	}

	END {
		print "Found " tablecount " tables";
	}
	' "$SCHEMAFILE"
}

##########################################################################
# Main

# Check for usage longopts
case "$1" in
	"--help"    ) usage;;
	"--version" ) version;;
esac

# Parse command line options
while getopts "hoV" opt
do
	case $opt in
	h  ) usage;;
	o  ) GETOPT_ORDERBY=1;;
	V  ) version;;
	\? ) exit_arg_error;;
	esac
done

shift $(($OPTIND - 1))

OUTPUTDIR="$1"
SCHEMAFILE="$2"

[ -n "$SCHEMAFILE" ] || exit_arg_error "missing schema file"
[ -n "$OUTPUTDIR" ] || exit_arg_error "missing output directory"

# Convert to real path
[ -d "$OUTPUTDIR" ] && OUTPUTDIR=$(readlink -f "$OUTPUTDIR")
[ -f "$SCHEMAFILE" ] && SCHEMAFILE=$(readlink -f "$SCHEMAFILE")

[ -d "$OUTPUTDIR" ] || exit_error "$OUTPUTDIR: No such directory"
[ -w "$OUTPUTDIR" ] || exit_error "$OUTPUTDIR: Write permission denied"
[ -f "$SCHEMAFILE" ] || exit_error "$SCHEMAFILE: No such file"
[ -r "$SCHEMAFILE" ] || exit_error "$SCHEMAFILE: Read permission denied"

FIELDDIR="$OUTPUTDIR/fields"
mkdir -p "$FIELDDIR" || exit_error

echo "Generating tables and fields from $(basename "$SCHEMAFILE")..."

parse_schema || exit_error

echo "Output saved to $OUTPUTDIR"
echo "Tables saved to import.tables"
echo "Field files saved to fields/*.fields"

exit 0

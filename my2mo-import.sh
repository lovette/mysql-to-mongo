#!/bin/bash
#
# Simplify importing data files with mongoimport.
#
# Copyright (c) 2011 Lance Lovette. All rights reserved.
# Licensed under the BSD License.
# See the file LICENSE.txt for the full license text.
#
# Available from https://github.com/lovette/mysql-to-mongo

CMDPATH=$(readlink -f "$0")
CMDNAME=$(basename "$CMDPATH")
CMDDIR=$(dirname "$CMDPATH")
CMDARGS=$@

MY2MO_IMPORT_VER="1.0.1"

GETOPT_DRYRUN=0
GETOPT_TABDELIMITED=0

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

# safe_import(args)
# Executes mongoimport unless dry run option is set
function safe_import()
{
	if [ $GETOPT_DRYRUN -eq 0 ]; then
		eval mongoimport $@
	else
		echo "mongoimport $@"
	fi
}

# gettablenames(path)
# Outputs table names (first column) from 'path'
function gettablenames()
{
	grep -v "^#" "$1" | cut -d" " -f1
}

# getfieldnames(path)
# Outputs field names (first column) from 'path'
function getfieldnames()
{
	grep -v "^#" "$1" | cut -d" " -f1
}

# Print version and exit
function version()
{
	echo "my2mo-import $MY2MO_IMPORT_VER"
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
	echo "Runs 'mongoimport' to import a set of comma-delimited data files"
	echo "from a database export. The list of tables and fields to import"
	echo "are read from an 'import.tables' file and a set of *.fields files."
    echo "The 'import.tables' and fields files can be created from scratch or"
	echo "from an SQL database schema by my2mo-fields."
    echo
	echo "Usage: my2mo-import [OPTION]... OUTPUTDIR CSVDIR IMPORTDB [-- IMPORTOPTIONS]"
	echo
	echo "Options:"
    echo "  OUTPUTDIR      Directory with import.tables and fields directory"
    echo "  CSVDIR         Directory with data files"
    echo "  IMPORTDB       Mongo database to import into"
	echo "  IMPORTOPTIONS  Options to pass directly to mongoimport"
	echo "  -h, --help     Show this help and exit"
	echo "  -n             Dry run; do not import"
	echo "  -t             Data files are tab-delimited"
	echo "  -V, --version  Print version and exit"
	echo
	echo "Report bugs to <https://github.com/lovette/mysql-to-mongo/issues>"

	exit 0
}   
 
# importtable(table)
function importtable()
{
	csvpath="$CSVDIR/$table.csv"
	fieldpath="$FIELDSDIR/$table.fields"
	filetype="csv"

	[ $GETOPT_TABDELIMITED -eq 1 ] && filetype="tsv"

	[ -f "$csvpath" ] || { echo "...$table, skipped (no data file)"; continue; }
	[ -f "$fieldpath" ] || exit_error "...$table, no field file found!"

	# Create the list of column names to import as comma-delimited list
	fields=( $(getfieldnames "$fieldpath") )
	fields="${fields[@]}"
	fields=${fields// /, }

	[ -n "$fields" ] || exit_error "...$table, no import fields defined!"

	echo "...$table"

	(
		echo
		echo "-- BEGIN TABLE: $table"
		echo "fields: $fields"
		safe_import --db "$IMPORTDB" --type "$filetype" --drop -c "$table" --file "$csvpath" --fields "${fields// /}" $IMPORTARGS
		[ $? -eq 0 ] || echo_stderr "see $(basename "$LOGPATH") for details"
		echo "-- END TABLE: $table"

	) >> "$LOGPATH"
}

##########################################################################
# Main


# Check for usage longopts
case "$1" in
	"--help"    ) usage;;
	"--version" ) version;;
esac

# Parse command line options
while getopts "hntV" opt
do
	case $opt in
	h  ) usage;;
	n  ) GETOPT_DRYRUN=1;;
	t  ) GETOPT_TABDELIMITED=1;;
	V  ) version;;
	\? ) exit_arg_error;;
	esac
done

shift $(($OPTIND - 1))

OUTPUTDIR="$1"
shift
CSVDIR="$1"
shift
IMPORTDB="$1"
shift

# Pass remaining arguments to mongoimport
if [ "$1" == "--" ]; then
	shift
	IMPORTARGS="$@"
elif [ -n "$1" ]; then
	exit_arg_error "mongoimport arguments must be preceded by '--'"
fi

[ -n "$OUTPUTDIR" ] || exit_arg_error "missing output directory"
[ -n "$CSVDIR" ] || exit_arg_error "missing data directory"
[ -n "$IMPORTDB" ] || exit_arg_error "missing import database"

# Convert to real path
[ -d "$OUTPUTDIR" ] && OUTPUTDIR=$(readlink -f "$OUTPUTDIR")
[ -d "$CSVDIR" ] && CSVDIR=$(readlink -f "$CSVDIR")

TABLESPATH="$OUTPUTDIR/import.tables"
FIELDSDIR="$OUTPUTDIR/fields"
LOGPATH="$OUTPUTDIR/mongoimport.log"

[ -d "$OUTPUTDIR" ] || exit_error "$OUTPUTDIR: No such directory"
[ -w "$OUTPUTDIR" ] || exit_error "$OUTPUTDIR: Write permission denied"
[ -d "$CSVDIR" ] || exit_error "$CSVDIR: No such directory"
[ -r "$CSVDIR" ] || exit_error "$CSVDIR: Read permission denied"
[ -d "$FIELDSDIR" ] || exit_error "$FIELDSDIR: No such directory"
[ -r "$FIELDSDIR" ] || exit_error "$FIELDSDIR: Read permission denied"
[ -f "$TABLESPATH" ] || exit_error "$TABLESPATH: No such file"
[ -r "$TABLESPATH" ] || exit_error "$TABLESPATH: Read permission denied"

# We need to know if any of our pipe commands fail, not just the last one
set -o pipefail

TABLES=( $(gettablenames "$TABLESPATH") )
[ $? -eq 0 ] || exit_error
[ ${#TABLES[@]} -gt 0 ] || exit_error "No tables found"

echo "Importing ${#TABLES[@]} tables into Mongo database '$IMPORTDB'..."

echo "Results of mongoimport of ${#TABLES[@]} tables into Mongo database '$IMPORTDB'..." > "$LOGPATH"

for table in "${TABLES[@]}"
do
	importtable "$table"
done

echo "Import complete!"

exit 0

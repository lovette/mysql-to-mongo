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

MY2MO_IMPORT_VER="1.0.2"

OUTPUTDIR="."
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

# safe_exec(args)
# Executes args unless dry run option is set
function safe_exec()
{
	if [ $GETOPT_DRYRUN -eq 0 ]; then
		eval $@
	else
		echo "$@"
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
	echo "Usage: my2mo-import [OPTION]... CSVDIR IMPORTDB [-- IMPORTOPTIONS]"
	echo
	echo "Options:"
    echo "  CSVDIR         Directory with data files"
    echo "  IMPORTDB       Mongo database to import into"
	echo "  IMPORTOPTIONS  Options to pass directly to mongoimport"
    echo "  -d DIRECTORY   Directory with import.tables and fields directory"
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
	local table="$1"
	local csvpath="$CSVDIR/$table.csv"
	local fieldpath="$FIELDSDIR/$table.fields"
	local filetype="csv"

	[ $GETOPT_TABDELIMITED -eq 1 ] && filetype="tsv"

	[ -f "$csvpath" ] || exit_error "...$table, no data file found!"
	[ -f "$fieldpath" ] || exit_error "...$table, no field file found!"

	# Create the list of column names to import as comma-delimited list
	local fields=( $(getfieldnames "$fieldpath") )
	fields="${fields[@]}"
	fields=${fields// /, }

	[ -n "$fields" ] || exit_error "...$table, no import fields defined!"

	echo "...$table"

	(
		echo
		echo "-- BEGIN TABLE: $table"
		echo "fields: $fields"
		safe_exec mongoimport --db "$IMPORTDB" --type "$filetype" --drop -c "$table" --file "$csvpath" --fields "${fields// /}" $IMPORTARGS
		[ $? -eq 0 ] || echo_stderr "see $(basename "$LOGPATH") for details"
		echo "-- END TABLE: $table"

	) >> "$LOGPATH"
}

# importtablejoin(table, table.field, table.field, sortfield)
function importtablejoin()
{
	local newtable="$1"
	local jointable1=$(echo "$2" | cut -d. -f1)
	local jointable2=$(echo "$3" | cut -d. -f1)
	local joinfield1=$(echo "$2" | cut -d. -f2)
	local joinfield2=$(echo "$3" | cut -d. -f2)
	local sortfield="$4"

	[ -n "$newtable" ] || exit_error "invalid join syntax"
	[ -n "$jointable1" ] || exit_error "invalid join syntax"
	[ -n "$jointable2" ] || exit_error "invalid join syntax"
	[ -n "$joinfield1" ] || exit_error "invalid join syntax"
	[ -n "$joinfield2" ] || exit_error "invalid join syntax"
	[ -n "$sortfield" ] || exit_error "invalid join syntax"

    local csvpath1="$CSVDIR/$jointable1.csv"
    local csvpath2="$CSVDIR/$jointable2.csv"

	[ -f "$csvpath1" ] || exit_error "$csvpath1: No such file"
	[ -f "$csvpath2" ] || exit_error "$csvpath2: No such file"

    local fieldpath1="$FIELDSDIR/$jointable1.fields"
    local fieldpath2="$FIELDSDIR/$jointable2.fields"

	[ -f "$fieldpath1" ] || exit_error "$fieldpath1: No such file"
	[ -f "$fieldpath2" ] || exit_error "$fieldpath2: No such file"

	local fieldindex1=$(grep -v "^#" "$fieldpath1" | grep -n "$joinfield1" | cut -d: -f1)
	local fieldindex2=$(grep -v "^#" "$fieldpath2" | grep -n "$joinfield2" | cut -d: -f1)

	[ -n "$fieldindex1" ] || exit_error "$jointable1.$joinfield1: No such field"
	[ -n "$fieldindex2" ] || exit_error "$jointable2.$joinfield2: No such field"

	local newfields=( "$joinfield1" $(getfieldnames "$fieldpath1" | grep -v "$joinfield1") $(getfieldnames "$fieldpath2" | grep -v "$joinfield2") )

	OLD_IFS="$IFS"
	IFS=$'\n'
	local sortfieldindex=$(echo "${newfields[*]}" | grep -n "$sortfield" | cut -d: -f1)
	IFS="$OLD_IFS"
	[ -n "$sortfieldindex" ] || exit_error "$newtable.$sortfield: No such field in joined table"

	newfields="${newfields[@]}"
	newfields=${newfields// /, }

	echo "...$newtable (join)"

	(
		echo
		echo "-- BEGIN TABLE: $newtable"
		echo "joining: $jointable1, $jointable2 where $joinfield1 = $joinfield2"
		echo "fields: $newfields"

		if [ $GETOPT_DRYRUN -eq 1 ]; then
			echo join -1 "$fieldindex1" -2 "$fieldindex2" -a 1 -t "\\t"  \<\(sort -t "\\t" -k "$fieldindex1" "$csvpath1"\) \<\(sort -t "\\t" -k "$fieldindex2" "$csvpath2"\) \|
			[ "$sortfield" = "-" ] || echo "sort -n -t '\\t' -k $sortfieldindex" \|
			safe_exec mongoimport --db "$IMPORTDB" --type tsv --drop -c "$newtable" --fields "${newfields// /}" $IMPORTARGS
		elif [ "$sortfield" = "-" ]; then
			join -1 "$fieldindex1" -2 "$fieldindex2" -a 1 -t $'\t' <(sort -t $'\t' -k "$fieldindex1" "$csvpath1") <(sort -t $'\t' -k "$fieldindex2" "$csvpath2") \
				| safe_exec mongoimport --db "$IMPORTDB" --type tsv --drop -c "$newtable" --fields "${newfields// /}" $IMPORTARGS
		else
			join -1 "$fieldindex1" -2 "$fieldindex2" -a 1 -t $'\t' <(sort -t $'\t' -k "$fieldindex1" "$csvpath1") <(sort -t $'\t' -k "$fieldindex2" "$csvpath2") \
				| sort -n -t $'\t' -k "$sortfieldindex" \
				| safe_exec mongoimport --db "$IMPORTDB" --type tsv --drop -c "$newtable" --fields "${newfields// /}" $IMPORTARGS
		fi

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
while getopts "d:hntV" opt
do
	case $opt in
	d  ) OUTPUTDIR="$OPTARG";;
	h  ) usage;;
	n  ) GETOPT_DRYRUN=1;;
	t  ) GETOPT_TABDELIMITED=1;;
	V  ) version;;
	\? ) exit_arg_error;;
	esac
done

shift $(($OPTIND - 1))

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
JOINTABLESPATH="$OUTPUTDIR/join.tables"
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

JOINTABLES=( )
[ -s "$JOINTABLESPATH" ] && JOINTABLES=( $(grep -v "^#" "$JOINTABLESPATH") )
[ ${#JOINTABLES[@]} -eq 0 ] || [ $GETOPT_TABDELIMITED -eq 1 ] || exit_error "join.tables requires tab-delimited data (-t)"
jointablesmod=$(( ${#JOINTABLES[@]} % 4 ))
[ $jointablesmod -eq 0 ] || exit_error "$JOINTABLESPATH: invalid format"

echo "Importing ${#TABLES[@]} tables into Mongo database '$IMPORTDB'..."

echo "Results of mongoimport of ${#TABLES[@]} tables into Mongo database '$IMPORTDB'..." > "$LOGPATH"

for table in "${TABLES[@]}"
do
	importtable "$table"
done

for (( i=0, max="${#JOINTABLES[@]}"; i < max; i+=4 ))
do
	importtablejoin "${JOINTABLES[$i]}" "${JOINTABLES[$i+1]}" "${JOINTABLES[$i+2]}" "${JOINTABLES[$i+3]}"
done

echo -e "\nImport complete!" >> "$LOGPATH"
echo "Import complete!"

exit 0

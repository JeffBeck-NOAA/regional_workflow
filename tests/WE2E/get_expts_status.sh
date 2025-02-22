#!/bin/bash 

#
#-----------------------------------------------------------------------
#
# This script updates and reports back the workflow status of all active
# forecast experiments under a specified base directory (expts_basedir).  
# It must be supplied exactly one argument, which is the full path to the
# experiments base directory.  
# 
# The script first determines which of the subdirectories under the base 
# directory represent active experiments (see below for how this is done).
# For all such experiments, it calls the workflow (re)launch script to 
# update the status of the workflow and prints the status out to screen.
# It also generates a status report file in the base directory that 
# contains the last num_log_lines lines (defined below) of each experiment's 
# workflow log file [which is generated by the (re)launch script] and thus 
# has information on which tasks may have succeeded/failed].
#
#-----------------------------------------------------------------------
#

#
#-----------------------------------------------------------------------
#
# Do not allow uninitialized variables.
#
#-----------------------------------------------------------------------
#
set -u
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# The current script should be located in the "tests" subdirectory of the
# workflow's top-level directory, which we denote by homerrfs.  Thus,
# homerrfs is the directory one level above the directory in which the
# current script is located.  Set homerrfs accordingly.
#
#-----------------------------------------------------------------------
#
homerrfs=${scrfunc_dir%/*/*}
#
#-----------------------------------------------------------------------
#
# Set directories.
#
#-----------------------------------------------------------------------
#
ushdir="$homerrfs/ush"
#
#-----------------------------------------------------------------------
#
# Source bash utility functions.
#
#-----------------------------------------------------------------------
#
. $ushdir/source_util_funcs.sh
#
#-----------------------------------------------------------------------
#
# Set the usage message.
#
#-----------------------------------------------------------------------
#
usage_str="\
Usage:

  ${scrfunc_fn} \\
    expts_basedir=\"...\" \\
    [verbose=\"...\"]

The arguments in brackets are optional.  The arguments are defined as
follows:

expts_basedir:
Full path to the experiments base directory, i.e. the directory containing 
the experiment subdirectories.

num_log_lines:
Optional integer specifying the number of lines from the end of the 
workflow launch log file (log.launch_FV3LAM_wflow) of each test to 
include in the status report file that this script generates.

verbose:
Optional verbosity flag.  Should be set to \"TRUE\" or \"FALSE\".  Default
is \"FALSE\".
"
#
#-----------------------------------------------------------------------
#
# Check to see if usage help for this script is being requested.  If so,
# print it out and exit with a 0 exit code (success).
#
#-----------------------------------------------------------------------
#
help_flag="--help"
if [ "$#" -eq 1 ] && [ "$1" = "${help_flag}" ]; then
  print_info_msg "${usage_str}"
  exit 0
fi
#
#-----------------------------------------------------------------------
#
# Specify the set of valid argument names for this script or function.
# Then process the arguments provided to it on the command line (which
# should consist of a set of name-value pairs of the form arg1="value1",
# arg2="value2", etc).
#
#-----------------------------------------------------------------------
#
valid_args=( \
  "expts_basedir" \
  "num_log_lines" \
  "verbose" \
  )
process_args valid_args "$@"
#
#-----------------------------------------------------------------------
#
# Set the default value of "num_log_lines".
#
#-----------------------------------------------------------------------
#
num_log_lines=${num_log_lines:-"40"}
#
#-----------------------------------------------------------------------
#
# Make the default value of "verbose" "FALSE".  Then make sure "verbose"
# is set to a valid value.
#
#-----------------------------------------------------------------------
#
verbose=${verbose:-"FALSE"}
check_var_valid_value "verbose" "valid_vals_BOOLEAN"
verbose=$(boolify $verbose)
#
#-----------------------------------------------------------------------
#
# Verify that the required arguments to this script have been specified.
# If not, print out an error message and exit.
#
#-----------------------------------------------------------------------
#
help_msg="\
Use
  ${scrfunc_fn} ${help_flag}
to get help on how to use this script."

if [ -z "${expts_basedir}" ]; then
  print_err_msg_exit "\
The argument \"expts_basedir\" specifying the base directory containing
the experiment directories was not specified in the call to this script.  \
${help_msg}"
fi
#
#-----------------------------------------------------------------------
#
# Check that the specified experiments base directory exists and is 
# actually a directory.  If not, print out an error message and exit.
#
#-----------------------------------------------------------------------
#
if [ ! -d "${expts_basedir}" ]; then
  print_err_msg_exit "
The specified experiments base directory (expts_basedir) does not exit 
or is not actually a directory:
  expts_basedir = \"${expts_basedir}\""
fi
#
#-----------------------------------------------------------------------
#
# Create an array containing the names of the subdirectories in the 
# experiment base directory.
#
#-----------------------------------------------------------------------
#
cd_vrfy "${expts_basedir}"
#
# Get a list of all subdirectories (but not files) in the experiment base 
# directory.  Note that the ls command below will return a string containing
# the subdirectory names, with each name followed by a backslash and a 
# newline.
#
subdirs_list=$( \ls -1 -d */ )
#
# Remove all backslashes from the ends of the subdirectory names.
#
subdirs_list=$( printf "${subdirs_list}" "%s" | sed -r 's|/||g' )
#
# Create an array out of the string containing the newline-separated list
# of subdirectories.
#
subdirs_list=( ${subdirs_list} )
#
#-----------------------------------------------------------------------
#
# Loop through the elements of the array subdirs_list and create an array
# containing a list of all active experiment subdirectories under the
# experiment base directory.  These active subdirectories will be further
# processed later below.  Here, by "active" experiment subdirectory, we
# mean a subdirectory that (1) contains a forecast experiment (i.e. was
# was created by the experiment generation scripts) and (2) does not 
# represent an old experiment whose workflow status is no longer relevant.
# For this purpose, for each element in subdirs_list, we: 
#
# 1) Change location to the subdirectory.
#
# 2) Check whether an experiment variable definitions file (var_defns.sh)
#    exists.  If so, we assume the subdirectory is an experiment directory.
#    If not, we assume it is not, in which case the subdirectory will 
#    not be added to the list of active experiment subdirectories.
#
# 3) If the subdirectory is an experiment directory, ensure that it is
#    an active experiment, i.e. that it is not an old experiment that 
#    has been renamed and whose experiment status is thus irrelevant.  
#    For this purpose, we source the variable definitions file in order
#    to have available the workflow variable EXPT_SUBDIR that contains
#    the name of the experiment when it was first created.  If this 
#    matches the name of the current subdirectory, then add the latter 
#    to the list of active experiment subdirectories; otherwise, do not.  
#    In the latter case, we are assuming that the original experiment 
#    subdirectory was renamed (e.g. to something like the orginal name 
#    with the string "_old001" appended) and thus does not contain an 
#    active experiment whose workflow status is of interest.
#
# 4) Change location back to the experiments base directory.
#
#-----------------------------------------------------------------------
#
separator="======================================"

var_defns_fn="var_defns.sh"
j="0"
expt_subdirs=()

print_info_msg "\
Checking for active experiment directories in the specified experiments
base directory (expts_basedir):
  expts_basedir = \"${expts_basedir}\"
..."

num_subdirs="${#subdirs_list[@]}"
for (( i=0; i<=$((num_subdirs-1)); i++ )); do

  subdir="${subdirs_list[$i]}"
  msg="
$separator
Checking whether the subdirectory 
  \"${subdir}\"
contains an active experiment..."
  print_info_msg "$verbose" "$msg"

  cd_vrfy "${subdir}"
#
# If a variable definitions file does not exist, print out a message 
# and move on to the next subdirectory.
#
  if [ ! -f "${var_defns_fn}" ]; then

    print_info_msg "$verbose" "
The current subdirectory (subdir) under the experiments base directory
(expts_basedir) does not contain an experiment variable defintions file
(var_defns_fn):
  expts_basedir = \"${expts_basedir}\"
  subdir = \"${subdir}\"
  var_defns_fn = \"${var_defns_fn}\"
Thus, we will assume it is not an experiment directory and will not add 
it to the list of active experiments subdirectories whose workflow status
must be checked."
#
# If a variable definitions file does exist, then...
#
  else
#
# Source the variable definitions file.
#
    . "./${var_defns_fn}"
#
# If the workflow variable EXPT_SUBDIR is the same as the name of the
# current subdirectory, then assume this subdirectory contains an active
# experiment.  In this case, print out a message and add its name to the 
# list of such experiments.
#
    if [ "${EXPT_SUBDIR}" = "$subdir" ]; then

      print_info_msg "$verbose" "
The current subdirectory (subdir) under the experiments base directory
(expts_basedir) contains an active experiment:
  expts_basedir = \"${expts_basedir}\"
  subdir = \"${subdir}\"
Adding the current subdirectory to the list of active experiment 
subdirectories whose workflow status must be checked."

      expt_subdirs[$j]="$subdir"
      j=$((j+1))
#
# If the workflow variable EXPT_SUBDIR is not the same as the name of 
# the current subdirectory, then assume this subdirectory contains an 
# "inactive" that has been renamed.  In this case, print out a message
# and move on to the next subdirectory (whithout adding the the name of
# the currend subdirectory to the list of active experiments).
#
    else

      print_info_msg "$verbose" "
The current subdirectory (subdir) under the experiments base directory
(expts_basedir) contains an experiment whose original name (EXPT_SUBDIR)
does not match the name of the current subdirectory:
  expts_basedir = \"${expts_basedir}\"
  subdir = \"${subdir}\"
  EXPT_SUBDIR = \"${EXPT_SUBDIR}\"
Thus, we will assume that the current subdirectory contains an inactive
(i.e. old) experiment whose workflow status is not relevant and will not 
add it to the list of active experiment subdirectories whose workflow 
status must be checked."

    fi

  fi

  print_info_msg "$verbose" "\
$separator
"
#
# Change location back to the experiments base directory.
#
  cd_vrfy "${expts_basedir}"
  
done
#
#-----------------------------------------------------------------------
#
# Get the number of active experiments for which to check the workflow 
# status and print out an informational message.
#
#-----------------------------------------------------------------------
#
num_expts="${#expt_subdirs[@]}"
expt_subdirs_str=$( printf "  \'%s\'\n" "${expt_subdirs[@]}" )
print_info_msg "
The number of active experiments found is:
  num_expts = ${num_expts}
The list of experiments whose workflow status will be checked is:
${expt_subdirs_str}
"
#
#-----------------------------------------------------------------------
#
# Set the name and full path of the file in which the status report will
# be saved.  If such a file already exists, rename it.
#
#-----------------------------------------------------------------------
#
yyyymmddhhmn=$( date +%Y%m%d%H%M )
expts_status_fn="expts_status_${yyyymmddhhmn}.txt"
expts_status_fp="${expts_basedir}/${expts_status_fn}"

# Note that the check_for_preexist_dir_file function assumes that there
# is a variable named "VERBOSE" in the environment.  Set that before 
# calling the function.
VERBOSE="TRUE"
check_for_preexist_dir_file "${expts_status_fp}" "rename"
#
#-----------------------------------------------------------------------
#
# Loop through the elements of the array expt_subdirs.  For each element
# (i.e. for each active experiment), change location to the experiment 
# directory and call the script launch_FV3LAM_wflow.sh to update the log 
# file log.launch_FV3LAM_wflow.  Then take the last num_log_lines of 
# this log file (along with an appropriate message) and add it to the 
# status report file.
#
#-----------------------------------------------------------------------
#
launch_wflow_fn="launch_FV3LAM_wflow.sh"
launch_wflow_log_fn="log.launch_FV3LAM_wflow"

for (( i=0; i<=$((num_expts-1)); i++ )); do

  expt_subdir="${expt_subdirs[$i]}"
  msg="\
$separator
Checking workflow status of experiment \"${expt_subdir}\" ..."
  print_info_msg "$msg"
#
# Change location to the experiment subdirectory, call the workflow launch
# script to update the workflow launch log file, and capture the output 
# from that call.
#
  cd_vrfy "${expt_subdir}"
  launch_msg=$( "${launch_wflow_fn}" 2>&1 )
  log_tail=$( tail -n ${num_log_lines} "${launch_wflow_log_fn}" )
#
# Print the workflow status to the screen.
#
  # The "tail -1" is to get only the last occurrence of "Workflow status"
  wflow_status=$( printf "${log_tail}" | grep "Workflow status:" | tail -1 )
  # Not sure why this doesn't work to strip leading spaces.
#  wflow_status="${wflow_status## }"
  # Remove leading spaces.
  wflow_status=$( printf "${wflow_status}" "%s" | sed -r 's|^[ ]*||g' )
  print_info_msg "${wflow_status}"
  print_info_msg "\
$separator
"
#
# Combine message above with the last num_log_lines lines from the workflow 
# launch log file and place the result in the status report file.
#
  msg=$msg"
${wflow_status}

The last ${num_log_lines} lines of this experiment's workflow launch log file 
(\"${launch_wflow_log_fn}\") are:

${log_tail}


"
  print_info_msg "$msg" >> "${expts_status_fp}"
#
# Change location back to the experiments base directory.
#
  cd_vrfy "${expts_basedir}"

done

print_info_msg "\
A status report has been created in:
  expts_status_fp = \"${expts_status_fp}\"

DONE."

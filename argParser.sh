#!/bin/bash
# Class definition for argParser objects

# turn on extended debugging so that we can access function arguments from sub-functions
shopt -s extdebug

# argParser.cloneArray(): Clones associative arrays; used for caching/restoring parsed switches
argParser.cloneArray() {
	source="$1"
	dest="$2"
	unset $dest
	declare -Ag $dest

	eval keys=$(eval "echo \"($(echo \${!$source[@]}))\"")
	eval values=$(eval "echo \"($(echo \${$source[@]}))\"")

	count=${#keys[@]}
	for i in $(seq 0 $[count - 1])
	do
		eval "$dest[${keys[i]}]='${values[i]}'"
	done
}

# argParser.areArraysEqual(): takes two names of non-associate arrays and compares the values
#	to determine if arrays are the same. Both values and positions within the array of those
#	values must be the same to evaluate true; otherwise function evaluates false
argParser.areArraysEqual() {
	arr1=$1
	arr2=$2
	
	# if they aren't the same length, return false
	[ $(eval "echo \${#$arr1[@]}") -ne $(eval "echo \${#$arr2[@]}") ] && return 1
	
	# compare elements 1-by-1
	maxIndex=$[$(eval "echo \${#$arr1[@]}") - 1]
	for i in $(seq 0 $maxIndex)
	do
		# if the elements don't match return false
		[ "$(eval echo "\${$arr1[i]}")" != "$(eval echo "\${$arr2[i]}")" ] && return 1
	done
	
	# everything matches; return true
	: && return
}

# argParser.getCaller(): looks up the name of the function/script that is making an
#	argParser request
argParser.getCaller() {
	local func fnStack=${FUNCNAME[@]}
	for func in $fnStack
	do
		if ! grep -q "^argParser\." <<< $func; then
			echo $func
			return
		fi
	done
	return 1
}

# argParser.loadScope(): loads the appropriate array of switches based on the caller
argParser.loadScope() {
	argParser_caller=$(argParser.getCaller)
	local caller=$argParser_caller
	if [ "$caller" != "$argParser_lastCaller" ]; then
		# our script/function scope changed; (re)load switches
		
		if [ $(eval echo \${#argParser_args_$caller[@]}) -eq 0 ]; then
			# we haven't parsed the args for this caller yet; do it now

			# process arguments passed to calling function
			argParser.getRawArgs
			argParser.parse "${argParser_rawArgs[@]}"
			
			# cache these args so we don't have to re-parse then next time
			argParser.cloneArray argParser_args argParser_args_$caller
			argParser.cloneArray argParser_rawArgs argParser_rawArgs_$caller
			argParser_lastCaller=$caller
		else
			# we've parsed the args for this caller before; reload them
			argParser.cloneArray argParser_args_$caller argParser_args
		fi
	else
		# make sure nothing has changed
		argParser.getRawArgs
		if ! argParser.areArraysEqual argParser_rawArgs argParser_rawArgs_caller; then
			# the raw arguments changed; re-parse
			argParser.parse "${argParser_rawArgs[@]}"
			
			# cache these args so we don't have to re-parse then next time
			argParser.cloneArray argParser_args argParser_args_$caller
			argParser.cloneArray argParser_rawArgs argParser_rawArgs_$caller
		fi
	fi

}

# argParser.main(): parses provided command line arguments and saves in an assoc array
argParser.parse() {
	local key value keyLen
	
	# reset the argParser_args variable so we don't retain ghost switches
	unset argParser_args
	declare -Ag argParser_args
	
	# loop over all args passed and parse the switches and values
	while [ $# -gt 0 ]
	do
		if grep  '='  <<< "$1" | cut -f1 -d= | grep -qvP ' '; then
			# argument takes the form key=VALUE
			key=$(cut -f1 -d= <<< "$1")
			value="$(cut -f2- -d= <<< "$1")"
			argParser_args[$key]="$value"
			shift
		else
			key="$1"
			if grep -q '^[^-]' <<< "$2"; then
				# argument takes the form --key VALUE or -k VALUE
				argParser_args[$key]="$2"
				shift
				shift
			else
				if grep -q '^-[^-]' <<< "$key"; then
					# argument takes the form -kVALUE or has no value
					keyLen=${#key}
					if [ $keyLen -gt 2 ]; then
						# argument takes the form -kVALUE
						value=${key:2}
					else
						# switch has no value and is of the form -k
						value='true'
					fi
					key=${key:0:2}
					argParser_args[$key]="$value"
				else
					# switch has no value and is of the form --key
					argParser_args[$key]='true'
				fi
				shift
			fi
		fi
	done
}

# argParser.getSwitches(): returns a space-delimited list of switches that were used
argParser.getSwitches() {
	argParser.loadScope
	# cannot use echo because it will fail in some cases
	tee /dev/null <<< $(tr ' ' '\n' <<< ${!argParser_args[@]}| tac | tr '\n' ' ')
}

# argParser.hasSwitch(): expects one or more space-delimited switches. Outputs a space-delimited list of all
#	matching switches that were used. If at least one switch as found, this function returns
#	with a status that evaluates to true. If none were found, this function returns with a
#	status that evaluates to false.
argParser.hasSwitches() {
	argParser.loadScope
	local testSwitches includedSwitches foundSwitches
	testSwitches="$@"
	includedSwitches="$(argParser.getSwitches)"
	([ -z "$includedSwitches" ] || [ -z "$testSwitches" ]) && return 1
	# look for $testSwitches within the $includedSwitches when script/function was called
	foundSwitches="$(grep -oP "(${includedSwitches// /|})( |$)" <<< "$testSwitches" | tr -d '\n' | grep -oP '[^ ].*' | grep -oP '.*[^ ]')"
	if [ ! -z "$foundSwitches" ]; then
		# print out a space-delimited list of switches found; we can't use echo for this because
		# it will lie if only a single switches is returned and is one of the following: -e -E -n
		cat <<< "$foundSwitches"
		return
	else
		return 1
	fi
}

argParser.getMissingSwitches() {
	argParser.loadScope
	local requiredSwitches includedSwitches missingSwitches
	requiredSwitches="$(tr ' ' '\n' <<< "$@")"
	includedSwitches="$(argParser.getSwitches | grep -oP '.*[^ ]' | tr ' ' '|')"
	([ -z "$includedSwitches" ] || [ -z "$requiredSwitches" ]) && return 1
	# look for $requiredSwitches within the $includedSwitches when script/function was called
	missingSwitches="$(grep -vP "($includedSwitches)( |$)" <<< "$requiredSwitches" | tr '\n' ' ' | grep -oP '.*[^ ]')"
	if [ ! -z "$missingSwitches" ]; then
		# print out a space-delimited list of switches found; we can't use echo for this because
		# it will lie if only a single switches is returned and is one of the following: -e -E -n
		cat <<< "$missingSwitches"
		return
	else
		return 1
	fi
}

# argParser.getArg(): accepts one or more switches and returns the associated value for the
#	first-occuring switch that was passed to getArg. So long as the switch was
#	found, the function returns with a status that evaluates to true, otherwise
#	it returns with a status that evaluates to false.
argParser.getArg() {
	argParser.loadScope
	local switches firstMatchingSwitch
	if switches=$(argParser.hasSwitches $@); then
		firstMatchingSwitch=$(cut -f1 -d' ' <<< "$switches")
		cat <<< "${argParser_args[$firstMatchingSwitch]}"
		return
	fi
	return 1
}

# argParser.isValidVarName(): helper function for setArgVars(); checks validity of string passed to be
#	used as a variable name
argParser.isValidVarName() {
    echo "$1" | grep -q '^[_[:alpha:]][_[:alpha:][:digit:]]*$' && return || return 1
}

# argParser.setArgVars(): iterates through args and creates variables named according to the switches with
#	values that correspond to the values of the switches
argParser.setArgVars() {
	argParser.loadScope
	local key varName value
	for key in ${!argParser_args[*]}
	do
		# strip dashes from front of switch
		varName=$(grep -oP '[^-].*' <<< "$key")
		# get value associated with switch
		value="${argParser_args[$key]}"
		if argParser.isValidVarName $varName; then
			# the variable name looks good; set the variable.
			eval "$varName=\"$value\""
		else
			# notify of failure to stderr
			echo -e "Could not set $varName=$value\n$varName is not a valid variable name" >&2
		fi
	done
}

# argParser.getRawArgs(): This function looks up who made the call for arguments and
#	then looks up the arguments that are associated with that caller and returns just those 
#	arguments in their unprocessed form.
argParser.getRawArgs() {
	unset argParser_rawArgs
	argParser_rawArgs=()
	local i=0 skip=0 j=0
	while [ "${FUNCNAME[i]}" != "$argParser_caller" ]
	do
		let $[skip+=${BASH_ARGC[i++]}]
	done
	count=${BASH_ARGC[i]}
	j=0
	for i in $(seq $skip $[skip+count-1] | tac)
	do
		argParser_rawArgs[j++]="${BASH_ARGV[$i]}"
	done
}

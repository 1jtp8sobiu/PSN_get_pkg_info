#!/bin/sh -ue

usage()
{
  printf -- 'usage: %s [-h] [-u] [-o] [-n] [-l INPUTFILE] [-v] [-r] [DIR ...]\n' "$(basename "${0}")"
  printf -- '\n'
  printf -- 'Search info files with analysis data of package files.\n'
  printf -- '\n'
  printf -- 'positional arguments:\n'
  printf -- '  DIR  Path to directory to process.\n'
  printf -- '\n'
  printf -- 'optional arguments:\n'
  printf -- '  -h   Show this help message and exit.\n'
  printf -- '  -u   Output unique values only.\n'
  printf -- '  -c   Additionally count unique values.\n'
  printf -- '  -o   Use grep --only-matching for GREP_OUTPUT. Useful in combination with unique values.\n'
  printf -- '  -n   No file names in results via grep -h for GREP_OUTPUT. Useful in combination with unique values.\n'
  printf -- '  -l   Take initial file list from specified input file (per each directory).\n'
  printf -- '  -v   Use xargs --verbose to show each grep command.\n'
  printf -- '  -r   Replace default directories with dirs instead of appending these.\n'
  printf -- '\n'
  printf -- 'default directories:\n'
  printf -- '  %s\n' "${DEFAULTDIRS}"
  exit 2
}

set_variable_once()
{
  local VARNAME VALUE

  VARNAME="${1}"
  shift
  #
  eval VALUE=\"\${${VARNAME}:-}\"
  if [ -z "${VALUE}" ]
   then
    eval "${VARNAME}=\"$@\""
  else
    printf -- '[ERROR] %s already set\n' "${VARNAME}"
    HELP=1
  fi
}

main()
{
  ## Localize and initialize variables
  local OPTION OPTARG OPTIND
  local HELP INITIALFILELIST UNIQUE DOCOUNT REPLACEDIRS VERBOSE ONLYMATCHING NOFILENAMES
  local DEFAULTDIRS DIRS DIR
  local IFS OLDIFS TABIFS
  local GREP GREP_OUTPUT GREP_DISPLAY FILELIST NEWFILELIST LINE REEVAL VALUE
  local MAXCOUNT COUNT
  MAXCOUNT=99
  #
  for COUNT in $(seq 1 "${MAXCOUNT}")
   do
    local "$(eval printf -- 'GREP_%s' "${COUNT}")"
    unset "$(eval printf -- 'GREP_%s' "${COUNT}")"
  done
  #
  for COUNT in $(seq 1 "${MAXCOUNT}")
   do
    local "$(eval printf -- 'VALUE_%s' "${COUNT}")"
    unset "$(eval printf -- 'VALUE_%s' "${COUNT}")"
  done
  #
  OLDIFS="${IFS}"
  TABIFS="$(printf -- '\t')"

  ## Set default directories
  unset DEFAULTDIRS
  DEFAULTDIRS="${DEFAULTDIRS:+${DEFAULTDIRS} }PS3"
  DEFAULTDIRS="${DEFAULTDIRS:+${DEFAULTDIRS} }PSX"
  DEFAULTDIRS="${DEFAULTDIRS:+${DEFAULTDIRS} }PSP"
  DEFAULTDIRS="${DEFAULTDIRS:+${DEFAULTDIRS} }PSV"
  DEFAULTDIRS="${DEFAULTDIRS:+${DEFAULTDIRS} }PSM"
  #
  DEFAULTDIRS="${DEFAULTDIRS:+${DEFAULTDIRS} }PS4"
  #
  DIRS="${DEFAULTDIRS}"

  ## Process command line options
  while getopts 'hl:ucrvon' OPTION
   do
    case "${OPTION}" in
     ('h'|'?') HELP=1 ;;
     ('u') set_variable_once UNIQUE 1 ;;
     ('c') set_variable_once DOCOUNT 1 ;;
     ('o') set_variable_once ONLYMATCHING "-o" ;;
     ('n') set_variable_once NOFILENAMES "-h" ;;
     ('l') set_variable_once INITIALFILELIST "${OPTARG}" ;;
     ('v') set_variable_once VERBOSE "--verbose" ;;
     ('r') set_variable_once REPLACEDIRS 1 ;;
    esac
  done
  shift $(( ${OPTIND} - 1))

  ## Process positional parameters
  if [ "${REPLACEDIRS:-0}" -eq 1 ]
   then
    unset DIRS
    if [ "${#}" -le 0 ]
     then
      printf -- '[ERROR] No directories stated\n'
      HELP=1
    fi
  fi

  ## Check options
  [ "${HELP:-0}" -eq 0 ] || usage

  ## Define multiple grep patterns GREP_<n> with options to determine the wanted package info files
  ##   To INCLUDE matching files use '-l' (lower case) as the first parameter
  ##   To EXCLUDE matching files use '-L' (upper case) as the first parameter
  ## Define grep pattern GREP_OUTPUT for the final result output
  ##   -l/-L will be removed, so GREP_<n> can be re-used
  ## Separate parameters with TAB (TAB will be used as IFS on grep commands)
  ## Use REEVAL=1 if ${DIR} is part of your grep statement.
  ##   Take care of the necessary extra escaping of special chars (backslash, quotes, etc.)
  ## Use VALUE_<n> as supporting variables.
  ##
  ## Examples:
  ## GREP_1='-l	-e	^Pkg_Header\[\"TYPE\".*:.* = 0x1$'
  ## GREP_OUTPUT="${GREP_1:+${GREP_1}	}-e	^Pkg_Header\\[\\\"HDRSIZE\\\".*"
  #
  ## PKG3 Header Types: TYPE
  #GREP_OUTPUT="-e	^Pkg_Header\\[\\\"TYPE\\\".*"
  #
  ## PKG3 Header Type 1 or 2: HDRSIZE
  #GREP_1='-l	-e	^Pkg_Header\[\"TYPE\".*:.* = 0x1$'
  #GREP_1='-l	-e	^Pkg_Header\[\"TYPE\".*:.* = 0x2$'
  #GREP_2='-l	-e	^Pkg_Header\[\"MAGIC\".*:.* = 0x7f504b47$'
  #GREP_OUTPUT='-e	^Pkg_Header\[\"HDRSIZE\".*'
  #GREP_OUTPUT='-e	^Pkg_Header\[\"HDRSIZE\".*	-e	^results\[\"PLATFORM\".*'
  #
  ## KEYINDEX
  #GREP_OUTPUT='-E	-e	KEYINDEX.*:[[:space:]]+[[:digit:]]+	-e	Key Index[[:space:]]+[[:digit:]]+'
  #
  ## Specific KEYINDEX (GREP_1 only) or different KEYINDEX in a single package (GREP_1 & GREP_2)
  #VALUE_1='0'
  #GREP_1="-l	-E	-e	KEYINDEX.*:[[:space:]]+${VALUE_1}[[:space:]]+"
  #GREP_2="-l	-P	-e	Key Index[[:space:]]+(?!${VALUE_1}[[:space:]]+)" ; ## different KEYINDEX in a single package ("not VALUE_1" via PCRE lookahead)
  #GREP_OUTPUT="-E	-e	KEYINDEX.*:[[:space:]]+[[:digit:]]+	-e	Key Index[[:space:]]+[[:digit:]]+"
  ## SFO Category
  #GREP_OUTPUT='-e	Pkg_Sfo_Values\[\"CATEGORY\"'
  #GREP_OUTPUT='-E	-e	Pkg_Sfo_Values\[\"CATEGORY\"[[:space:]]+\]: gd.{1}'
  #
  ## Wrong platform
  #REEVAL=1
  #GREP_1='-L	-e	^Results\\[\\\"PLATFORM\\\".*: ${DIR%x}$'
  #GREP_OUTPUT='-e	^Results\[\"PLATFORM\".*'
  #
  #GREP_OUTPUT='-e	^Results\[\"PKG_CONTENT_TYPE\".*0x1 '
  #
  ## search special item/file names
  #VALUE_1='sce_sys/package/digs.bin' ; VALUE_2='18' ; ## as it is extracted encrypted (not decrypted) as body.bin; only in PSV packages with flags 0xa0007018/0xa0007818 (no other items with 0x...18)
  #VALUE_1='sce_sys/package/cert.bin' ; VALUE_2='17' ; ## as it is extracted encrypted (not decrypted) as body.bin; only in PSV packages with flags 0xa0007017 (no other items with 0x...17)
  #VALUE_1='sce_sys/package/body.bin' ; VALUE_2='03' ; ## see also digs.bin; only in PSM packages in contents/runtime/ with flags 0xc0000003
  #VALUE_1='sce_sys/package/head.bin' ; VALUE_2='03' ; ## only in PSM packages in contents/runtime/ with flags 0xc0000003
  #VALUE_1='sce_sys/package/tail.bin' ; VALUE_2='03' ; ## only in PSM packages in contents/runtime/ with flags 0xc0000003
  #VALUE_1='sce_sys/package/stat.bin' ; VALUE_2='03' ; ## only in PSM packages in contents/runtime/ with flags 0xc0000003
  #VALUE_1='content_id' ; VALUE_2='' ; ## none found, no item with this name
  #VALUE_1='EBOOT\.PBP' ; VALUE_2='' ; ## ...
  #VALUE_1='\.PBP' ; VALUE_2='' ; ## ...
  #VALUE_1='runtime' ; VALUE_2='' ; ## ...
  #VALUE_1='texture\.enc' ; VALUE_2='' ; ## ...
  #GREP_OUTPUT="-E	-e	Flags[[:space:]]+.*Name[[:space:]]+\\\".*${VALUE_1}" ;  ## search item name part
  #GREP_OUTPUT="-E	-e	Flags[[:space:]]+0x[[:xdigit:]]{6}${VALUE_2}.*\$" ;  ## search item flags part
  #GREP_OUTPUT="-E	-e	Name[[:space:]]+\\\".*${VALUE_1}" ;  ## search item name part
  #
  #GREP_1="-L	-E	-e	Name[[:space:]]+\\\".*${VALUE_1}" ;  ## exclude packages with a .PBP item
  #GREP_2='-L	-e	^Results\[\"PKG_CONTENT_TYPE\".* 0x9 ' ;  ## exclude packages with a content type 0x9 (PS3/PSP Theme)
  #GREP_OUTPUT='-m1	-e	""' ;  ## grep first line of file
  #
  ## Determine read-ahead size for python script
  #GREP_OUTPUT='-e	^Results\[\"ITEMS_INFO\".*\"FILE_OFS_END\".*'
  #
  ## Themes
  #GREP_1='-l	-e	Pkg_Meta_Data\[0x02\]: Desc "Content Type" Value 9'
  #GREP_1='-l	-e	\[0x02\]: Desc "Content Type" Value 9'
  #GREP_OUTPUT='-e	\[0x03\]'
  #GREP_OUTPUT='-e	Pkg_Meta_Data\[0x0e\]: '
  # reverse
  #GREP_1='-l	-e	\[0x03\]: Desc "Package Type/Flags" Value 0000048c'
  #GREP_1='-l	-e	\[0x03\]: Desc "Package Type/Flags" Value 0000020c'
  #GREP_OUTPUT='-e	\[0x02\]'
  #
  ## PS2 Classic
  #GREP_1='-l	-e	Pkg_Sfo_Values\["CATEGORY"          \]: 2P'
  #GREP_OUTPUT='-e	\[0x02\]'
  #
  ## PSX
  #GREP_1='-l	-e	Pkg_Sfo_Values\["CATEGORY"          \]: 2P'
  #GREP_OUTPUT='-e	PSX_TITLE_ID'
  #GREP_1='-l	-e	Pkg_Meta_Data\[0x02\]: Desc "Content Type" Value 1'
  #GREP_OUTPUT='-e	Pkg_Meta_Data\[0x02\]	-e	Pkg_Meta_Data\[0x06\]	-e	Pkg_Header\["CONTENT_ID"'
  #
  ## _DIFFER
  #GREP_1='-l	-e	_DIFFER'
  #GREP_OUTPUT='-e	Pkg_Meta_Data\[0x02\]	-e	_DIFFER'
  #
  ## Firmware Versions (PS3_SYSTEM_VER, PSP_SYSTEM_VER, PSP2_DISP_VER, PSP2_SYSTEM_VER)
  #GREP_OUTPUT='-e	_SYSTEM_VER'
  #GREP_OUTPUT='-e	_DISP_VER'
  #
  ## Versions (APP_VER, DISC_VERSION, HRKGMP_VER, VERSION, TARGET_APP_VER)
  #GREP_OUTPUT='-e	Pkg_Sfo_Values\[\".*APP_VER.*\"	-e	Pkg_Sfo_Values\[\".*VERSION.*\"'
  #
  ## Unlock Keys and their titles
  #GREP_1='-l	-e	Pkg_Meta_Data\[0x03\]:.*Value 0000048c$'
  #GREP_OUTPUT='-e	Results\["SFO_TITLE"'
  #
  ## EBOOT.BIN/.EDAT/.SDAT
  #GREP_OUTPUT='-i	-e	Name[[:space:]]\+".*eboot.bin"'
  #GREP_OUTPUT='-i	-e	Name[[:space:]]\+".*\.edat"'
  #GREP_OUTPUT='-i	-e	Name[[:space:]]\+".*\.sdat"'
  #GREP_OUTPUT='-i	-e	NPD[[:space:]]\+.*$'
  #GREP_OUTPUT='-i	-e	NPD[[:space:]]\+.*License 0.*$'
  #GREP_OUTPUT='-i	-e	NPD Version 0.*$'
  #GREP_OUTPUT='-i	-e	NPD Version 1.*$	--before-context=1	-n'
  #GREP_OUTPUT='-i	-e	Name[[:space:]]\+".*ISO\.BIN\.EDAT"'
  #GREP_OUTPUT='-i	-e	PLATFORM'
  #GREP_OUTPUT='-i	-e	CONTENT_ID'
  #
  ## RETAIL/DEBUG
  #GREP_OUTPUT='-e	^Pkg_Header\["REV"[[:space:]]\+|.*\]: .*'
  #GREP_1='-L	-e	^Pkg_Header\["REV"[[:space:]]\+|.*\]: 0x8.*'
  #GREP_OUTPUT='-e	^.*PKG Source.*'
  #
  ## USRDIR
  #GREP_OUTPUT='-i	-e	Name[[:space:]]\+".*USRDIR.*"'

  ## Clean-up and check GREP_OUTPUT pattern
  GREP_OUTPUT="$(printf -- '%s' "${GREP_OUTPUT:-}" | sed -r -e 's#(-l|-L)##g ; s#[\t]+#\t#g ; s#(^\t|\t$)##g')"
  #
  if [ -z "${GREP_OUTPUT:-}" ]
   then
    printf -- '[ERROR] No OUTPUT grep pattern defined inside script\n'
    return 0
  fi

  ## Process directories
  for DIR in ${DIRS:-} "${@}"
   do
    if [ ! -d "${DIR}" ]
     then
      printf -- '[ERROR] Directory "%s" does not exist\n' "${DIR}"
      continue
    fi
    [ -d "${DIR}/_pkginfo" ] || continue
    #
    printf -- '# >>>>> Searching analysis data in "%s" for grep patterns...\n' "${DIR}"

    ## Determine package info files for output via GREP_<n> patterns
    ## --> Starting file list
    [ -d "${DIR}/_tmp" ] || mkdir "${DIR}/_tmp"
    FILELIST="$(tempfile -d "${DIR}/_tmp")"
    : >"${FILELIST}"
    if [ -n "${INITIALFILELIST:-}" ]
     then
      printf -- '# > Initial file list taken from %s\n' "${DIR}/${INITIALFILELIST}"
      if [ -s "${DIR}/${INITIALFILELIST}" ]
       then
        IFS=
        while read -r LINE
         do
          if [ -n "${LINE}" ]
           then
            printf -- '%s\0' "${DIR}/_pkginfo/${LINE}" >>"${FILELIST}"
            LINE=""
          fi
        done < "${DIR}/${INITIALFILELIST}"
        IFS="${OLDIFS}"
      fi
    else
      printf -- '%s' "${DIR}/_pkginfo" >"${FILELIST}"
    fi
    ## --> Process GREP_<n> patterns
    for COUNT in $(seq 1 "${MAXCOUNT}")
     do
      [ -s "${FILELIST}" ] || break
      #
      eval GREP=\"\${GREP_${COUNT}:-}\"
      [ -n "${GREP}" ] || break
      [ "${REEVAL:-0}" -eq 0 ] || eval GREP=\""${GREP}"\"
      printf -- '# > Grep %s: %s\n' "${COUNT}" "${GREP}" | sed -e 's#\t# #g'
      #
      NEWFILELIST="$(tempfile -d "${DIR}/_tmp")"
      IFS="${TABIFS}"
      #set -x
      { sort -z -- "${FILELIST}" | xargs -0 -r -L 10 ${VERBOSE:-} -- grep -R -Z ${GREP} -- >"${NEWFILELIST}" ; } || true
      #set +x
      IFS="${OLDIFS}"
      #
      rm "${FILELIST}"
      FILELIST="${NEWFILELIST}"
      #
      [ -s "${FILELIST}" ] || break
      #sort -z -- "${FILELIST}" | xargs -0 -r -L 1
    done  ## COUNT

    ## Show wanted output of remaining package info files via GREP_OUTPUT pattern
    if [ ! -s "${FILELIST}" ]
     then
      [ ! -e "${FILELIST}" ] || rm "${FILELIST}"
      printf -- 'No matches\n'
    else
      printf -- '# > Grep OUTPUT: %s\n' "${GREP_OUTPUT}" | sed -e 's#\t# #g'
      #sort -z -- "${FILELIST}" | xargs -0 -r -L 1
      #
      IFS="${TABIFS}"
      #set -x
      if [ "${UNIQUE:-0}" -eq 1 ]  ## unique values
       then
        if [ "${DOCOUNT:-0}" -eq 1 ]  ## count unique values
         then
          { sort -z -- "${FILELIST}" | xargs -0 -r -L 10 ${VERBOSE:-} -- grep -R ${NOFILENAMES:--H} ${ONLYMATCHING:-} ${GREP_OUTPUT} -- | sort | uniq -c ; } || true
        else
          { sort -z -- "${FILELIST}" | xargs -0 -r -L 10 ${VERBOSE:-} -- grep -R ${NOFILENAMES:--H} ${ONLYMATCHING:-} ${GREP_OUTPUT} -- | sort | uniq ; } || true
        fi
      else
        { sort -z -- "${FILELIST}" | xargs -0 -r -L 10 ${VERBOSE:-} -- grep -R ${NOFILENAMES:--H} ${ONLYMATCHING:-} ${GREP_OUTPUT} -- | sort ; } || true
      fi
      #set +x
      IFS="${OLDIFS}"
      #
      rm "${FILELIST}"
    fi

    unset FILELIST
    printf -- '\n'
  done  ## DIR

  return 0  ## leave function
}

main "${@}"

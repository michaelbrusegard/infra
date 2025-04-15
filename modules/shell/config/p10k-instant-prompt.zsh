[[ -t 0 && -t 1 && -t 2 && -o interactive && -o zle && -o no_xtrace ]] &&
  ! (( ${+__p9k_instant_prompt_disabled} || zsh_subshell || ${+zsh_script} || ${+zsh_execution_string} )) || return 0
() {
  emulate -l zsh -o no_hist_expand -o extended_glob -o no_prompt_bang -o prompt_percent -o no_prompt_subst -o no_aliases -o no_bg_nice -o typeset_silent -o no_rematch_pcre
  (( $+__p9k_trapped )) || { local -i __p9k_trapped; trap : int; trap "trap ${(q)__p9k_trapint:--} int" exit }
  local -a match reply mbegin mend
  local -i mbegin mend optind
  local match reply optarg ifs=$' \t\n\0'
  typeset -gi __p9k_instant_prompt_disabled=1
  [[ $zsh_version == 5.9 && $zsh_patchlevel == zsh-5.9-0-g73d3173 &&
     -z ${(m)term:#(screen*|tmux*)} &&
     ${#${(m)vte_version:#(<1-4602>|4801)}} == 0 &&
     $powerlevel9k_disable_instant_prompt != 'true' &&
     $powerlevel9k_instant_prompt != 'off' ]] || return
  typeset -g __p9k_instant_prompt_param_sig=$'1.20.14\c-a5.9\c-azsh-5.9-0-g73d3173\c-a\c-awezterm\c-a63\c-amichaelbrusegard%\c-a\c-a\c-a\c-a\c-a\c-a\c-a1\c-a0\c-a0\c-a\c-a%b%s%#%s%b\c-a1\c-autf-8\c-a\c-a\c-a0\c-a1\c-a/home/michaelbrusegard/.cache/antidote/romkatv/powerlevel10k\c-a\c-a\c-a\c-a\c-a1\c-a256\c-a0\c-a\c-a3\c-ad h m s\c-a0\c-a5\c-a/nix/store/x3caawkpnd8svp8a4pv56ahpbcrja74z-.p10k.zsh\c-a\c-a%f{7}%n%f%f{242}@%m%f\c-a\c-a%f{242}%n@%m%f\c-a4\c-atrue\c-averbose\c-a\c-adir\c-bvcs\c-bnewline\c-bprompt_char\c-a\c-a\c-a \c-afalse\c-a❮\c-a1\c-a❯\c-a1\c-a❮\c-a1\c-a❮\c-a5\c-a❯\c-a5\c-a❮\c-a5\c-afalse\c-a\c-acommand_execution_time\c-bvirtualenv\c-bcontext\c-bnewline\c-a\c-a\c-a \c-a242\c-a%d{%h:%m:%s}\c-afalse\c-aalways\c-a\c-a@\c-a1\c-a1\c-a${${${p9k_content/⇣* :⇡/⇣⇡}// }//:/ }\c-a*\c-a242\c-avcs-detect-changes\c-bgit-untracked\c-bgit-aheadbehind\c-a6\c-a:⇣\c-a\c-a0\c-a6\c-a:⇡\c-a\c-a\c-a\c-a242\c-a\c-a\c-afalse\c-a'
  local gitstatus_dir=/home/michaelbrusegard/.cache/antidote/romkatv/powerlevel10k/gitstatus
  local gitstatus_header=\#\ 3
  local -i zle_rprompt_indent=1
  local prompt_eol_mark=%b%s%\#%s%b
  [[ -n $ssh_client || -n $ssh_tty || -n $ssh_connection ]] && local ssh=1 || local ssh=0
  local cr=$'\r' lf=$'\n' esc=$'\e[' rs=$'\x1e' us=$'\x1f'
  local -i height=1
  local prompt_dir=/home/michaelbrusegard/.cache/p10k-michaelbrusegard

  (( _z4h_can_save_restore_screen == 1 )) && height=0

  local real_gitstatus_header
  if [[ -r $gitstatus_dir/install.info ]]; then
    ifs= read -r real_gitstatus_header <$gitstatus_dir/install.info || real_gitstatus_header=borked
  fi
  [[ $real_gitstatus_header == $gitstatus_header ]] || return
  zmodload zsh/langinfo zsh/terminfo zsh/system || return
  if [[ $langinfo[codeset] != (utf|utf)(-|)8 ]]; then
    local loc_cmd=$commands[locale]
    [[ -z $loc_cmd ]] && loc_cmd=/run/current-system/sw/bin/locale
    if [[ -x $loc_cmd ]]; then
      local -a locs
      if locs=(${(@m)$(locale -a 2>/dev/null):#*.(utf|utf)(-|)8}) && (( $#locs )); then
        local loc=${locs[(r)(#i)c.utf(-|)8]:-${locs[(r)(#i)en_us.utf(-|)8]:-$locs[1]}}
        [[ -n $lc_all ]] && local lc_all=$loc || local lc_ctype=$loc
      fi
    fi
  fi
  (( terminfo[colors] == 256 )) || return
  (( $+terminfo[cuu] && $+terminfo[cuf] && $+terminfo[ed] && $+terminfo[sc] && $+terminfo[rc] )) || return
  local pwd=${(%):-%/}
  [[ $pwd == /* ]] || return
  local prompt_file=$prompt_dir/prompt-${#pwd}
  local key=$pwd:$ssh:${(%):-%#}
  local content
  if [[ ! -e $prompt_file ]]; then
    typeset -gi __p9k_instant_prompt_sourced=47
    return 1
  fi
  { content="$(<$prompt_file)" } 2>/dev/null || return
  local tail=${content##*$rs$key$us}
  if (( ${#tail} == ${#content} )); then
    typeset -gi __p9k_instant_prompt_sourced=47
    return 1
  fi
  local _p9k__ipe
  local p9k_prompt=instant
  if [[ -z $p9k_tty || $p9k_tty == old && -n ${_p9k_tty:#$tty} ]]; then

    typeset -gx p9k_tty=old
    zmodload -f zsh/stat b:zstat || return
    zmodload zsh/datetime || return
    local -a stat
    if zstat -a stat +ctime -- $tty 2>/dev/null &&
      (( epochrealtime - stat[1] < 5.0000000000 )); then
      p9k_tty=new
    fi
  fi
  typeset -gx _p9k_tty=$tty
  local -i _p9k__empty_line_i=3 _p9k__ruler_i=3
  local -a _p9k_display_k=(-2/left 11 2/left 33 -1/right 35 1/left/dir 17 -2/left/vcs 19 -2/right/context 25 -1/left 33 1/right/virtualenv 23 1/right_frame 9 1/right 13 -2/right/virtualenv 23 2/right 35 -2/right 13 2/right_frame 31 -2/right_frame 9 empty_line 1 -1/left/prompt_char 39 2/left/prompt_char 39 1/right/context 25 -1 27 -2 5 1/left 11 -1/gap 37 -1/right_frame 31 -2/gap 15 1/left/vcs 19 1 5 1/left_frame 7 ruler 3 2 27 -1/left_frame 29 1/gap 15 2/gap 37 1/right/command_execution_time 21 2/left_frame 29 -2/left_frame 7 -2/right/command_execution_time 21 -2/left/dir 17)
  local -a _p9k__display_v=(empty_line hide ruler hide 1 show 1/left_frame show 1/right_frame show 1/left show 1/right show 1/gap show 1/left/dir show 1/left/vcs show 1/right/command_execution_time show 1/right/virtualenv show 1/right/context show 2 show 2/left_frame show 2/right_frame show 2/left show 2/right show 2/gap show 2/left/prompt_char show)
  function p10k() {
    emulate -l zsh -o no_hist_expand -o extended_glob -o no_prompt_bang -o prompt_percent -o no_prompt_subst -o no_aliases -o no_bg_nice -o typeset_silent -o no_rematch_pcre
  (( $+__p9k_trapped )) || { local -i __p9k_trapped; trap : int; trap "trap ${(q)__p9k_trapint:--} int" exit }
  local -a match reply mbegin mend
  local -i mbegin mend optind
  local match reply optarg ifs=$' \t\n\0'; [[ $langinfo[codeset] != (utf|utf)(-|)8 ]] && _p9k_init_locale && { [[ -n $lc_all ]] && local lc_all=$__p9k_locale || local lc_ctype=$__p9k_locale }
    [[ $1 == display ]] || return
    shift
    local -i k dump
    local opt prev new pair list name var
    while getopts ":ha" opt; do
      case $opt in
        a) dump=1;;
        h) return 0;;
        ?) return 1;;
      esac
    done
    if (( dump )); then
      reply=()
      shift $((optind-1))
      (( argc )) || set -- "*"
      for opt; do
        for k in ${(u@)_p9k_display_k[(i)$opt]:/(#m)*/$_p9k_display_k[$match]}; do
          reply+=($_p9k__display_v[k,k+1])
        done
      done
      return 0
    fi
    for opt in "${@:$optind}"; do
      pair=(${(s:=:)opt})
      list=(${(s:,:)${pair[2]}})
      if [[ ${(b)pair[1]} == $pair[1] ]]; then
        local ks=($_p9k_display_k[$pair[1]])
      else
        local ks=(${(u@)_p9k_display_k[(i)$pair[1]]:/(#m)*/$_p9k_display_k[$match]})
      fi
      for k in $ks; do
        if (( $#list == 1 )); then
          [[ $_p9k__display_v[k+1] == $list[1] ]] && continue
          new=$list[1]
        else
          new=${list[list[(i)$_p9k__display_v[k+1]]+1]:-$list[1]}
          [[ $_p9k__display_v[k+1] == $new ]] && continue
        fi
        _p9k__display_v[k+1]=$new
        name=$_p9k__display_v[k]
        if [[ $name == (empty_line|ruler) ]]; then
          var=_p9k__${name}_i
          [[ $new == hide ]] && typeset -gi $var=3 || unset $var
        elif [[ $name == (#b)(<->)(*) ]]; then
          var=_p9k__${match[1]}${${${${match[2]//\/}/#left/l}/#right/r}/#gap/g}
          [[ $new == hide ]] && typeset -g $var= || unset $var
        fi
      done
    done
  }

  () {
	[[ -z $p9k_toolbox_name ]] || return 0
	if [[ -f /run/.containerenv && -r /run/.containerenv ]]
	then
		local name=(${(q)${${(@m)${(f)"$(</run/.containerenv)"}:#name=*}#name=}}) 
		[[ ${#name} -eq 1 && -n ${name[1]} ]] || return 0
		typeset -g p9k_toolbox_name=${name[1]} 
	elif [[ -n $distrobox_enter_path ]]
	then
		local name=${(%):-%m} 
		if [[ -n $name && $name == $name* ]]
		then
			typeset -g p9k_toolbox_name=$name 
		fi
	fi
  }
  trap "unset -m _p9k__\*; unfunction p10k" exit
  local -a _p9k_t=("${(@ps:$us:)${tail%%$rs*}}")
  if [[ $+vte_version == 1 || $term_program == hyper ]] && (( $+commands[stty] )); then
    if [[ $term_program == hyper ]]; then
      local bad_lines=40 bad_columns=100
    else
      local bad_lines=24 bad_columns=80
    fi
    if (( lines == bad_lines && columns == bad_columns )); then
      zmodload -f zsh/stat b:zstat || return
      zmodload zsh/datetime || return
      local -a tty_ctime
      if ! zstat -a tty_ctime +ctime -- $tty 2>/dev/null || (( tty_ctime[1] + 2 > epochrealtime )); then
        local -f deadline=$((epochrealtime+0.025))
        local tty_size
        while true; do
          if (( epochrealtime > deadline )) || ! tty_size="$(command stty size 2>/dev/null)" || [[ $tty_size != <->" "<-> ]]; then
            (( $+_p9k__ruler_i )) || local -i _p9k__ruler_i=1
            local _p9k__g= _p9k__2r= _p9k__2r_frame=
            break
          fi
          if [[ $tty_size != "$bad_lines $bad_columns" ]]; then
            local lines_columns=(${=tty_size})
            local lines=$lines_columns[1]
            local columns=$lines_columns[2]
            break
          fi
        done
      fi
    fi
  fi
  typeset -ga __p9k_used_instant_prompt=("${(@e)_p9k_t[-3,-1]}")

  local -i prompt_height=${#${__p9k_used_instant_prompt[1]//[^$lf]}}
  (( height += prompt_height ))
  local _p9k__ret
  function _p9k_prompt_length() {
    local -i columns=1024
    local -i x y=${#1} m
    if (( y )); then
      while (( ${${(%):-$1%$y(l.1.0)}[-1]} )); do
        x=y
        (( y *= 2 ))
      done
      while (( y > x + 1 )); do
        (( m = x + (y - x) / 2 ))
        (( ${${(%):-$1%$m(l.x.y)}[-1]} = m ))
      done
    fi
    typeset -g _p9k__ret=$x
  }
  local out=${(%):-%b%k%f%s%u}
  if [[ $p9k_tty == old && ( $+vte_version == 0 && $term_program != hyper || $+_p9k__g == 0 ) ]]; then
    local mark=${(e)prompt_eol_mark}
    [[ $mark == "%b%s%#%s%b" ]] && _p9k__ret=1 || _p9k_prompt_length $mark
    local -i fill=$((columns > _p9k__ret ? columns - _p9k__ret : 0))
    out+="${(%):-$mark${(pl.$fill.. .)}$cr%b%k%f%s%u%e}"
  else
    out+="${(%):-$cr%e}"
  fi
  if (( _z4h_can_save_restore_screen != 1 )); then
    (( height )) && out+="${(pl.$height..$lf.)}$esc${height}a"
    out+="$terminfo[sc]"
  fi
  out+=${(%):-"$__p9k_used_instant_prompt[1]$__p9k_used_instant_prompt[2]"}
  if [[ -n $__p9k_used_instant_prompt[3] ]]; then
    _p9k_prompt_length "$__p9k_used_instant_prompt[2]"
    local -i left_len=_p9k__ret
    _p9k_prompt_length "$__p9k_used_instant_prompt[3]"
    if (( _p9k__ret )); then
      local -i gap=$((columns - left_len - _p9k__ret - zle_rprompt_indent))
      if (( gap >= 40 )); then
        out+="${(pl.$gap.. .)}${(%):-${__p9k_used_instant_prompt[3]}%b%k%f%s%u}$cr$esc${left_len}c"
      fi
    fi
  fi
  if (( _z4h_can_save_restore_screen == 1 )); then
    if (( height )); then
      out+="$cr${(pl:$((height-prompt_height))::\n:)}$esc${height}a$terminfo[sc]$out"
    else
      out+="$cr${(pl:$((height-prompt_height))::\n:)}$terminfo[sc]$out"
    fi
  fi
  if [[ -n "$tmpdir" && ( ( -d "$tmpdir" && -w "$tmpdir" ) || ! ( -d /tmp && -w /tmp ) ) ]]; then
    local tmpdir=$tmpdir
  else
    local tmpdir=/tmp
  fi
  typeset -g __p9k_instant_prompt_output=$tmpdir/p10k-instant-prompt-output-${(%):-%n}-$$
  { : > $__p9k_instant_prompt_output } || return
  print -rn -- "${out}${esc}?2004h" || return
  if (( $+commands[stty] )); then
    command stty -icanon 2>/dev/null
  fi
  local fd_null
  sysopen -ru fd_null /dev/null || return
  exec {__p9k_fd_0}<&0 {__p9k_fd_1}>&1 {__p9k_fd_2}>&2 0<&$fd_null 1>$__p9k_instant_prompt_output
  exec 2>&1 {fd_null}>&-
  typeset -gi __p9k_instant_prompt_active=1
  if (( _z4h_can_save_restore_screen == 1 )); then
    typeset -g _z4h_saved_screen
    -z4h-save-screen
  fi
  typeset -g __p9k_instant_prompt_dump_file=${xdg_cache_home:-~/.cache}/p10k-dump-${(%):-%n}.zsh
  if builtin source $__p9k_instant_prompt_dump_file 2>/dev/null && (( $+functions[_p9k_preinit] )); then
    _p9k_preinit
  fi
  function _p9k_instant_prompt_cleanup() {
    (( zsh_subshell == 0 && ${+__p9k_instant_prompt_active} )) || return 0
    emulate -l zsh -o no_hist_expand -o extended_glob -o no_prompt_bang -o prompt_percent -o no_prompt_subst -o no_aliases -o no_bg_nice -o typeset_silent -o no_rematch_pcre
  (( $+__p9k_trapped )) || { local -i __p9k_trapped; trap : int; trap "trap ${(q)__p9k_trapint:--} int" exit }
  local -a match reply mbegin mend
  local -i mbegin mend optind
  local match reply optarg ifs=$' \t\n\0'
    unset __p9k_instant_prompt_active
    exec 0<&$__p9k_fd_0 1>&$__p9k_fd_1 2>&$__p9k_fd_2 {__p9k_fd_0}>&- {__p9k_fd_1}>&- {__p9k_fd_2}>&-
    unset __p9k_fd_0 __p9k_fd_1 __p9k_fd_2
    typeset -gi __p9k_instant_prompt_erased=1
    if (( _z4h_can_save_restore_screen == 1 && __p9k_instant_prompt_sourced >= 35 )); then
      -z4h-restore-screen
      unset _z4h_saved_screen
    fi
    print -rn -- $terminfo[rc]${(%):-%b%k%f%s%u}$terminfo[ed]
    if [[ -s $__p9k_instant_prompt_output ]]; then
      command cat $__p9k_instant_prompt_output 2>/dev/null
      if (( $1 )); then
        local _p9k__ret mark="${(e)${prompt_eol_mark-%b%s%#%s%b}}"
        _p9k_prompt_length $mark
        local -i fill=$((columns > _p9k__ret ? columns - _p9k__ret : 0))
        echo -ne - "${(%):-%b%k%f%s%u$mark${(pl.$fill.. .)}$cr%b%k%f%s%u%e}"
      fi
    fi
    zshexit_functions=(${zshexit_functions:#_p9k_instant_prompt_cleanup})
    zmodload -f zsh/files b:zf_rm || return
    local user=${(%):-%n}
    local root_dir=${__p9k_instant_prompt_dump_file:h}
    zf_rm -f -- $__p9k_instant_prompt_output $__p9k_instant_prompt_dump_file{,.zwc} $root_dir/p10k-instant-prompt-$user.zsh{,.zwc} $root_dir/p10k-$user/prompt-*(n) 2>/dev/null
  }
  function _p9k_instant_prompt_precmd_first() {
    emulate -l zsh -o no_hist_expand -o extended_glob -o no_prompt_bang -o prompt_percent -o no_prompt_subst -o no_aliases -o no_bg_nice -o typeset_silent -o no_rematch_pcre
  (( $+__p9k_trapped )) || { local -i __p9k_trapped; trap : int; trap "trap ${(q)__p9k_trapint:--} int" exit }
  local -a match reply mbegin mend
  local -i mbegin mend optind
  local match reply optarg ifs=$' \t\n\0'; [[ $langinfo[codeset] != (utf|utf)(-|)8 ]] && _p9k_init_locale && { [[ -n $lc_all ]] && local lc_all=$__p9k_locale || local lc_ctype=$__p9k_locale }
    function _p9k_instant_prompt_sched_last() {
      (( ${+__p9k_instant_prompt_active} )) || return 0
      _p9k_instant_prompt_cleanup 1
      setopt no_local_options prompt_cr prompt_sp
    }
    zmodload zsh/sched
    sched +0 _p9k_instant_prompt_sched_last
    precmd_functions=(${(@)precmd_functions:#_p9k_instant_prompt_precmd_first})
  }
  zshexit_functions=(_p9k_instant_prompt_cleanup $zshexit_functions)
  precmd_functions=(_p9k_instant_prompt_precmd_first $precmd_functions)
  disable_update_prompt=true
} && unsetopt prompt_cr prompt_sp && typeset -gi __p9k_instant_prompt_sourced=47 ||
  typeset -gi __p9k_instant_prompt_sourced=${__p9k_instant_prompt_sourced:-0}

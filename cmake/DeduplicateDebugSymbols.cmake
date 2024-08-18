
# Mesen struggles to understand ca65 debug symbols if two values map to the same address

function(deduplicate_debug_symbols)
  set(options)
  set(oneValueArgs TARGET FILE)
  set(multiValueArgs)
  cmake_parse_arguments(PARSE_ARGV 0 "DBG" "${options}" "${oneValueArgs}" "${multiValueArgs}")

  # cmake_path(ABSOLUTE_PATH DBG_FILE OUTPUT_VARIABLE ABS_DBG_FILE)

  add_custom_command(TARGET ${DBG_TARGET}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -DDBG_FILE=${DBG_FILE} -P ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/DeduplicateDebugSymbols.cmake
    COMMENT "Deduplicating debug symbols")
endfunction()

function(_dedupe)
  set(options)
  set(oneValueArgs FILE)
  set(multiValueArgs)
  cmake_parse_arguments(PARSE_ARGV 0 "DBG" "${options}" "${oneValueArgs}" "${multiValueArgs}")
  string(TIMESTAMP time)
  message(NOTICE "${time} starting")
  # line by line appending is very slow, but we can filter out to just the lines we care about
  # during the first file read.
  file(COPY_FILE ${DBG_FILE} ${DBG_FILE}.orig)
  file(STRINGS ${DBG_FILE} skippedLines REGEX "^(version|file|line|span|scope|type)")
  file(STRINGS ${DBG_FILE} rawDbgFile   REGEX "^(sym|seg)")
  set(output)  # list
  set(symline) # list
  set(symline_id) # list
  set(symline_name) # list
  # set(symline_scope) # list
  set(symline_val) # list
  set(symline_seg) # list
  set(symline_type) # list
  # rom_seg_base_${val} is a "list" as well
  foreach(line ${rawDbgFile})
    if (NOT line MATCHES "^sym")
      if (line MATCHES "^seg.*id=([0-9]+).*start=(0x[a-zA-Z0-9]+).*ooffs=([0-9]+)")
        set(seg_id    ${CMAKE_MATCH_1})
        set(seg_start ${CMAKE_MATCH_2})
        set(seg_ooffs ${CMAKE_MATCH_3})
        math(EXPR seg_base "${seg_ooffs} - ${seg_start}" OUTPUT_FORMAT HEXADECIMAL)
        set(rom_seg_base_${seg_id} ${seg_base})
      endif()
      string(APPEND output "${line}\n")
      continue()
    endif()
    if (line MATCHES "name=\"([a-zA-Z0-9_-]+)\".*type=imp")
      set(prop_name ${CMAKE_MATCH_1})
      math(EXPR importcount_${prop_name} "${importcount_${prop_name}} + 1")
    elseif (line MATCHES "id=([0-9]+).*name=\"([a-zA-Z0-9_-]+)\".*(size=[0-9]+)?.*scope=([0-9]+).*val=(0x[a-zA-Z0-9]+).*seg=([0-9]+).*type=([a-zA-Z]+)")
      list(APPEND symline ${line})
      list(APPEND symline_id ${CMAKE_MATCH_1})
      list(APPEND symline_name ${CMAKE_MATCH_2})
      set(maybe_size ${CMAKE_MATCH_3})
      # list(APPEND symline_scope ${CMAKE_MATCH_4})
      math(EXPR symline_value "${CMAKE_MATCH_5}" OUTPUT_FORMAT DECIMAL)
      list(APPEND symline_val ${symline_value})
      list(APPEND symline_seg ${CMAKE_MATCH_6})
      list(APPEND symline_type ${CMAKE_MATCH_7})
      if (maybe_size MATCHES "size=([0-9]+)")
        set(symline_size_${symline_id} ${CMAKE_MATCH_1})
      endif()
    endif()
  endforeach()
  list(LENGTH symline list_len)
  math(EXPR list_len "${list_len} - 1" OUTPUT_FORMAT DECIMAL)
  foreach(index RANGE ${list_len})
    list(GET symline_val ${index} val)
    if (${val} LESS "8" OR ${val} GREATER_EQUAL "65536")
      continue()
    endif()
    list(GET symline_seg ${index} seg)
    set(seg_base "${rom_seg_base_${seg}}")
    list(GET symline_name ${index} symname)
    list(GET symline_type ${index} symtype)
    list(GET symline_id ${index} symid)
    set(score "1")
    if ("${symline_size_${symid}}" GREATER "0")
      math(EXPR score "${score} + 1")
    endif()
    if (${symtype} MATCHES "lab")
      math(EXPR score "${score} + 2")
    endif()
    if (${seg} GREATER "0")
      math(EXPR score "${score} + 1")
    endif()
    set(impcount "${importcount_${symname}}")
    if ("${impcount}" GREATER "0")
      math(EXPR score "${score} * (1 + ${impcount})")
    endif()

    list(GET symline ${index} line)
    list(APPEND valtosyms "valtosyms${seg}_${val}")
    list(APPEND valtosyms${seg}_${val} "${score} ${line}")
  endforeach()

  list(REMOVE_DUPLICATES valtosyms)
  list(LENGTH valtosyms list_len)
  math(EXPR list_len "${list_len} - 1" OUTPUT_FORMAT DECIMAL)
  foreach(index RANGE ${list_len})
    list(GET valtosyms ${index} seg_val)
    list(LENGTH "${seg_val}" inner_len)
    math(EXPR inner_len "${inner_len} - 1" OUTPUT_FORMAT DECIMAL)

    set(high_score "0")
    set(orig_line "")
    foreach(jindex RANGE ${inner_len})
      list(GET "${seg_val}" ${jindex} inner)
      string(REGEX MATCH "([0-9]+) (.*)" unused ${inner})
      set(score ${CMAKE_MATCH_1})
      if ("${score}" GREATER "${high_score}")
        set(orig_line ${CMAKE_MATCH_2})
      endif()
    endforeach()
    string(APPEND output "${orig_line}\n")
  endforeach()
  string(JOIN "\n" skipped ${skippedLines})
  string(JOIN "\n" output "${skipped}\n;${output}")
  file(WRITE ${DBG_FILE} ${output})
  string(TIMESTAMP time)
  message(NOTICE "${time} finished")
endfunction()

if(CMAKE_SCRIPT_MODE_FILE)
  message(STATUS "deduplicating debug symbols: ${DBG_FILE}")
  _dedupe(FILE ${DBG_FILE})
endif()



# Include this file in a top-level CMakeLists to build several CMake
# subprojects (which may depend on each other).
#
# When included, it will automatically parse a .gitsubprojects file if one is
# present in the same CMake source directory. The .gitsubprojects file
# contains lines in the form:
#   "git_subproject(<project> <giturl> <gittag>)"
# Will also parse Buildyard config files in the current directory and
# activate all configurations which have <NAME>_SUBPROJECT set.
#
# All the subprojects will be cloned and configured during the CMake configure
# step thanks to the 'git_subproject(project giturl gittag)' macro
# (also usable separately).
# The latter relies on the add_subproject(name) function to add projects as
# sub directories. See also: cmake command 'add_subdirectory'.
#
# The following targets are created by SubProject.cmake:
# - An 'update_git_subprojects_${PROJECT_NAME}' target to update the <gittag> of
#   all the .gitsubprojects entries to their latest respective origin/master ref
# - A generic 'update' target to execute 'update_git_subrojects' recursively
# - A <project>-all target to build only the given sub project
#
# To be compatible with the SubProject feature, (sub)projects might need to
# adapt their CMake scripts in the following way:
# - CMAKE_BINARY_DIR should be changed to PROJECT_BINARY_DIR
# - CMAKE_SOURCE_DIR should be changed to PROJECT_SOURCE_DIR
#
# Respects the following variables:
# - DISABLE_SUBPROJECTS: when set, does not load sub projects. Useful for
#   example for continuous integration builds
# - INSTALL_PACKAGES: command line cache variable which will "apt-get" or
#   "port install" the known system packages. Will be unset after installation.
# A sample project can be found at https://github.com/Eyescale/Collage.git

include(${CMAKE_CURRENT_LIST_DIR}/GitExternal.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/CMakeCompatibility.cmake)

if(TARGET git_subproject_${PROJECT_NAME}_done)
  return()
endif()
add_custom_target(git_subproject_${PROJECT_NAME}_done)

function(subproject_install_packages file name)
  if(NOT EXISTS ${file} OR NOT INSTALL_PACKAGES)
    return()
  endif()

  include(${file})
  string(TOUPPER ${name} NAME)

  if(${NAME}_DEB_DEPENDS AND CMAKE_SYSTEM_NAME MATCHES "Linux" )
    list(SORT ${NAME}_DEB_DEPENDS)
    list(REMOVE_DUPLICATES ${NAME}_DEB_DEPENDS)
    message("Running 'sudo apt-get install ${${NAME}_DEB_DEPENDS}'")
    execute_process(COMMAND sudo apt-get install ${${NAME}_DEB_DEPENDS})
  endif()
  if(${NAME}_PORT_DEPENDS AND APPLE)
    list(SORT ${NAME}_PORT_DEPENDS)
    list(REMOVE_DUPLICATES ${NAME}_PORT_DEPENDS)
    set(${NAME}_PORT_DEPENDS_UNI)
    foreach(__port ${${NAME}_PORT_DEPENDS})
      list(APPEND ${NAME}_PORT_DEPENDS_UNI ${__port} +universal)
    endforeach()
    message(
      "Running 'sudo port install ${${NAME}_PORT_DEPENDS} (+universal)'")
    execute_process(COMMAND sudo port install -p
      ${${NAME}_PORT_DEPENDS_UNI})
  endif()
endfunction()

function(add_subproject name)
  string(TOUPPER ${name} NAME)
  if(CMAKE_MODULE_PATH)
    # We're adding a sub project here: Remove parent's CMake
    # directories so they don't take precendence over the sub project
    # directories. Change is scoped to this function.
    list(REMOVE_ITEM CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/CMake
      ${PROJECT_SOURCE_DIR}/CMake/common)
  endif()

  list(LENGTH ARGN argc)
  if(argc GREATER 0)
    list(GET ARGN 0 path)
  else()
    set(path ${name})
  endif ()

  if(NOT EXISTS "${CMAKE_SOURCE_DIR}/${path}/")
    message(FATAL_ERROR "Sub project ${path} not found in ${CMAKE_SOURCE_DIR}")
  endif()

  option(SUBPROJECT_${name} "Build ${name} " ON)
  if(SUBPROJECT_${name})
    # if the project needs to do anything special when configured as a
    # sub project then it can check the variable ${PROJECT}_IS_SUBPROJECT
    set(${name}_IS_SUBPROJECT ON)
    set(${NAME}_FOUND ON PARENT_SCOPE)

    # set ${PROJECT}_DIR to the location of the new build dir for the project
    if(NOT ${name}_DIR)
      set(${name}_DIR "${CMAKE_BINARY_DIR}/${name}" CACHE PATH
        "Location of ${name} project" FORCE)
    endif()

    subproject_install_packages(
      "${CMAKE_SOURCE_DIR}/${path}/CMake/${name}.cmake" ${name})

    # add the source sub directory to our build and set the binary dir
    # to the build tree
    set(ADD_SUBPROJECT_INDENT "${ADD_SUBPROJECT_INDENT}   ")
    message("${ADD_SUBPROJECT_INDENT}========== ${path} ==========")
    add_subdirectory("${CMAKE_SOURCE_DIR}/${path}"
      "${CMAKE_BINARY_DIR}/${name}")
    message("${ADD_SUBPROJECT_INDENT}---------- ${path} ----------")
    set(${name}_IS_SUBPROJECT ON PARENT_SCOPE)
    # Mark globally that we've already used name as a sub project
    set_property(GLOBAL PROPERTY ${name}_IS_SUBPROJECT ON)
    # Create <project>-all target
    get_property(__targets GLOBAL PROPERTY ${name}_ALL_DEP_TARGETS)
    if(__targets)
      add_custom_target(${name}-all DEPENDS ${__targets})
    endif()
  endif()
endfunction()

macro(git_subproject name url tag)
  if(NOT BUILDYARD AND NOT DISABLE_SUBPROJECTS)
    string(TOUPPER ${name} NAME)
    set(TAG ${tag})
    if(SUBPROJECT_TAG AND NOT "${tag}" STREQUAL "release")
      set(TAG ${SUBPROJECT_TAG})
    endif()
    if(NOT ${NAME}_FOUND)
      get_property(__included GLOBAL PROPERTY ${name}_IS_SUBPROJECT)
      if(NOT EXISTS ${CMAKE_SOURCE_DIR}/${name})
        find_package(${name} QUIET CONFIG)
      elseif(__included) # already used as a sub project, just find it:
        find_package(${name} QUIET CONFIG HINTS ${CMAKE_BINARY_DIR}/${NAME})
      endif()
      if(NOT ${NAME}_FOUND)
        git_external(${CMAKE_SOURCE_DIR}/${name} ${url} ${TAG})
        add_subproject(${name})
        if(NOT ${NAME}_FOUND)
          find_package(${name} REQUIRED CONFIG) # find subproject "package"
          include_directories(${${NAME}_INCLUDE_DIRS})
        endif()
      endif()
    endif()
    get_property(__included GLOBAL PROPERTY ${name}_IS_SUBPROJECT)
    if(__included)
      list(APPEND __subprojects "${name} ${url} ${tag}")
    endif()
  endif()
endmacro()

# Interpret .gitsubprojects
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/.gitsubprojects")
  subproject_install_packages(
    "${CMAKE_SOURCE_DIR}/CMake/${PROJECT_NAME}.cmake" ${PROJECT_NAME})

  set(__subprojects) # appended on each git_subproject invocation
  include(.gitsubprojects)

  if(__subprojects)
    set(GIT_SUBPROJECTS_SCRIPT
      "${CMAKE_CURRENT_BINARY_DIR}/UpdateSubprojects.cmake")
    file(WRITE "${GIT_SUBPROJECTS_SCRIPT}"
      "file(WRITE .gitsubprojects \"# -*- mode: cmake -*-\n\")\n")
    foreach(__subproject ${__subprojects})
      string(REPLACE " " ";" __subproject_list ${__subproject})
      list(GET __subproject_list 0 __subproject_name)
      list(GET __subproject_list 1 __subproject_repo)
      set(__subproject_dir "${CMAKE_SOURCE_DIR}/${__subproject_name}")
      file(APPEND "${GIT_SUBPROJECTS_SCRIPT}"
        "execute_process(COMMAND ${GIT_EXECUTABLE} fetch origin -q\n"
        "  WORKING_DIRECTORY ${__subproject_dir})\n"
        "execute_process(COMMAND \n"
        "  ${GIT_EXECUTABLE} show-ref --hash=7 refs/remotes/origin/master\n"
        "  OUTPUT_VARIABLE newref OUTPUT_STRIP_TRAILING_WHITESPACE\n"
        "  WORKING_DIRECTORY ${__subproject_dir})\n"
        "if(newref)\n"
        "  file(APPEND .gitsubprojects\n"
        "    \"git_subproject(${__subproject_name} ${__subproject_repo} \${newref})\\n\")\n"
        "else()\n"
        "  file(APPEND .gitsubprojects \"git_subproject(${__subproject})\n\")\n"
        "endif()\n")
    endforeach()

    add_custom_target(update_git_subprojects_${PROJECT_NAME}
      COMMAND ${CMAKE_COMMAND} -P ${GIT_SUBPROJECTS_SCRIPT}
      COMMENT "Update ${PROJECT_NAME}/.gitsubprojects"
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")

    if(NOT TARGET update)
      add_custom_target(update)
    endif()
    add_dependencies(update update_git_subprojects_${PROJECT_NAME})
  endif()
endif()

# interpret Buildyard project.cmake and depends.txt configurations
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/depends.txt")
  file(READ depends.txt SUBPROJECT_DEPENDS)
  string(REGEX REPLACE "#[^\n]*" "" SUBPROJECT_DEPENDS "${SUBPROJECT_DEPENDS}")
  string(REGEX REPLACE "^\n" "" SUBPROJECT_DEPENDS "${SUBPROJECT_DEPENDS}")
  string(REGEX REPLACE "[ \n]" ";" SUBPROJECT_DEPENDS "${SUBPROJECT_DEPENDS}")

  list(LENGTH SUBPROJECT_DEPENDS SUBPROJECT_DEPENDS_LEFT)
  while(SUBPROJECT_DEPENDS_LEFT GREATER 2)
    list(GET SUBPROJECT_DEPENDS 0 SUBPROJECT_DEPENDS_DIR)
    list(GET SUBPROJECT_DEPENDS 1 SUBPROJECT_DEPENDS_REPO)
    list(GET SUBPROJECT_DEPENDS 2 SUBPROJECT_DEPENDS_TAG)
    list(REMOVE_AT SUBPROJECT_DEPENDS 0 1 2)
    list(LENGTH SUBPROJECT_DEPENDS SUBPROJECT_DEPENDS_LEFT)

    git_subproject(${SUBPROJECT_DEPENDS_DIR} ${SUBPROJECT_DEPENDS_REPO}
      ${SUBPROJECT_DEPENDS_TAG})
  endwhile()
endif()

file(GLOB _files *.cmake)
foreach(_file ${_files})
  string(REPLACE "${CMAKE_CURRENT_SOURCE_DIR}/" "" _config ${_file})
  list(APPEND _localFiles ${_config})

  string(REPLACE ".cmake" "" Name ${_config})
  get_filename_component(NAME ${Name} NAME)
  string(TOUPPER ${NAME} NAME)
  set(${NAME}_DIR ${BASEDIR})
  include(${_file})

  if(${NAME}_SUBPROJECT)
    if(NOT ${NAME}_REPO_TAG)
      set(${NAME}_REPO_TAG master)
    endif()
    git_subproject(${Name} ${${NAME}_REPO_URL} ${${NAME}_REPO_TAG})
  endif()
endforeach()

if("${CMAKE_SOURCE_DIR}" STREQUAL "${CMAKE_CURRENT_SOURCE_DIR}")
  unset(INSTALL_PACKAGES CACHE) # Remove after install in SubProject.cmake
endif()

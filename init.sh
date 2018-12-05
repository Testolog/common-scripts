#!/usr/bin/env bash

function atom_plugins(){
    apm install tablr autocomplete-sql autosave-onchange script
    return ${PIPESTATUS[0]}
}

#brew install gnu-sed

if [[ -x "$(command -v apm)" && ! -e ${AMP_INIT} ]]; then
      echo "install atom_plugins"
      atom_plugins
      touch ${AMP_INIT}
      #todo: append check of error
fi




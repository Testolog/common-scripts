PROCESS=()
while IFS='' read -r r; do PROCESS+=("$r"); done < <(ps -A -o "pid,ppid,%cpu,%mem,comm" | awk ' {OFS=","; print $1,$2,$3,$4,$5 }')
echo "${#PROCESS[*]}"

for row in "${PROCESS[@]:1}"; do
  splitarray=()
  while IFS= read -r r; do splitarray+=("$r"); done < <(echo "${row//,/\n}")
  pid=${splitarray[1]}
  ppid=${splitarray[2]}
  cpu=${splitarray[3]}
  mem=${splitarray[4]}
  comm=${splitarray[5]}
  if (($cpu > 10)); then
    echo "${row}"
    echo "$pid", "$comm"
  fi
  #  echo "${comm}"
done

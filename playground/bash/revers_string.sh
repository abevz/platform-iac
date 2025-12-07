#!/usr/bin/env bash
export IFS=" "
main() {
  for word in "$*"; do
    if [ -z "$word" ]; then
      continue
    else
      echo -n "$word" | rev
    fi
    echo ${#word}
    echo $word
  done
}

main "$@"

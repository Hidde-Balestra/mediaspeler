#!/usr/bin/env bash
# Controleert na `flutter build apk --release` dat R8 de mediabediening niet
# heeft weggehaald (anders doen de knoppen op het vergrendelscherm niets).
set -euo pipefail
usage="build/app/outputs/mapping/release/usage.txt"
if [ ! -f "$usage" ]; then
  echo "Geen $usage gevonden (draai eerst flutter build apk --release)." >&2
  exit 1
fi
# Door de compiler gegenereerde hulpklassen (InternalSynthetic) mogen wel weg.
removed=$(grep -E '^com\.ryanheise\.audioservice' "$usage" | grep -v 'InternalSynthetic' || true)
if [ -n "$removed" ]; then
  echo "R8 heeft delen van audio_service verwijderd:" >&2
  echo "$removed" >&2
  echo "Controleer android/app/proguard-rules.pro." >&2
  exit 1
fi
echo "OK: audio_service is volledig behouden in de release-build."

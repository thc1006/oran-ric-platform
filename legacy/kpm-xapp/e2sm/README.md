e2sm directory includes E2SM-KPMv2.01 ASN.1 related definition.
- header: Includes C header files
- lib: Includes C source files
- src: Include E2SMv2 and E2SM-KPMv2.01 ASN definition, you can use asn1c tools to compile into C language. `asn1c -pdu=auto -fcompound-names -fno-include-deps -findirect-choice  -gen-PER -gen-OER -no-gen-example O-RAN.WG3.E2SM-KPM-v02.01.asn1 O-RAN.WG3.E2SM-v02.01.asn1`
- main.c: This code aims to test the result of the wrapper
- wrapper.h: This wrapper defines some functions for the encoding/decoding
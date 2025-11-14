package control

/*
#include <e2ap/wrapper.h>
#cgo LDFLAGS: -le2apwrapper
#cgo CFLAGS: -I/usr/local/include/e2ap
*/
import "C"

import (
	"errors"
	"fmt"
	"unsafe"
)

type E2ap struct {
}

func (e *E2ap) RICIndicationDecode(Payload []byte) (Indication *RICIndication, err error) {
	fmt.Println("RICIndication Payload =", Payload)

	cptr := unsafe.Pointer(&Payload[0])
	Indication = &RICIndication{}

	// Call E2AP Wrapper to decode
	DecodedIndication := C.Decode_RIC_Indication(cptr, C.size_t(len(Payload)))
	if DecodedIndication == nil {
		return nil, errors.New("e2ap wrapper is unable to decode indication message due to wrong or invalid payload")
	}
	defer C.Free_RIC_Indication(DecodedIndication)

	//Parse decoded RIC Indication C structure to Golang Structure
	Indication.RequestorID = int32(DecodedIndication.RequestorID)
	Indication.RequestInstanceID = int32(DecodedIndication.RequestInstanceID)
	Indication.RanfunctionID = int32(DecodedIndication.RanfunctionID)
	Indication.ActionID = int32(DecodedIndication.ActionID)
	Indication.IndicationSN = int32(DecodedIndication.IndicationSN)
	Indication.IndicationType = int32(DecodedIndication.IndicationType)

	IndicationHeader_C := unsafe.Pointer(DecodedIndication.IndicationHeader)
	Indication.IndicationHeader = C.GoBytes(IndicationHeader_C, C.int(DecodedIndication.IndicationHeaderSize))
	Indication.IndicationHeaderSize = int32(DecodedIndication.IndicationHeaderSize)

	IndicationMessage_C := unsafe.Pointer(DecodedIndication.IndicationMessage)
	Indication.IndicationMessage = C.GoBytes(IndicationMessage_C, C.int(DecodedIndication.IndicationMessageSize))
	Indication.IndicationMessageSize = int32(DecodedIndication.IndicationMessageSize)

	/*
		CallProcessID_C := unsafe.Pointer(DecodedIndication.CallProcessID)
		Indication.CallProcessID = C.GoBytes(CallProcessID_C, C.int(DecodedIndication.CallProcessIDSize))
		Indication.CallProcessIDSize = int32(DecodedIndication.CallProcessIDSize)
	*/
	return
}

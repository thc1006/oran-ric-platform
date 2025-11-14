#ifndef _WRAPPER_H_
#define _WRAPPER_H_

//Include Libraries
#include "E2AP-PDU.h"
#include "InitiatingMessage.h"
#include "ProtocolIE-Container.h"
#include "ProtocolIE-Field.h"

#ifdef __cplusplus
extern "C" {
#endif

//Type Declaration
typedef struct RICIndication {
	long RequestorID;
	long RequestInstanceID;
	long RanfunctionID;
	long ActionID;
	long IndicationSN;            /*Optional*/
	long IndicationType;
	uint8_t *IndicationHeader;
	size_t IndicationHeaderSize;
	uint8_t *IndicationMessage;
	size_t IndicationMessageSize;
	uint8_t *CallProcessID;       /*Optional*/
	size_t CallProcessIDSize;     /*Optional*/
} RICIndication;

//Function Definition
E2AP_PDU_t* Decode_E2AP_PDU(void* Buffer, size_t Buf_size);

RICIndication* Decode_RIC_Indication(void *Buffer, size_t Buf_size);
void Free_RIC_Indication(RICIndication* RicIndication);

#ifdef __cplusplus
}
#endif

#endif
#include <errno.h>
#include "wrapper.h"

E2AP_PDU_t* Decode_E2AP_PDU(void* Buffer, size_t Buf_size){
    asn_dec_rval_t Result;
    E2AP_PDU_t *PDU = 0;
    Result = aper_decode_complete(NULL, &asn_DEF_E2AP_PDU, (void **)&PDU, Buffer, Buf_size);
    if(Result.code == RC_OK) {
        return PDU;
    } else {
        ASN_STRUCT_FREE(asn_DEF_E2AP_PDU, PDU);
        return NULL;
    }
}

RICIndication* Decode_RIC_Indication(void *Buffer, size_t Buf_size){
    E2AP_PDU_t *PDU = Decode_E2AP_PDU(Buffer, Buf_size);
    if(PDU == NULL){
        fprintf(stderr, "Failed to decode E2AP PDU\n");
        return NULL;
    }

    if (PDU->present == E2AP_PDU_PR_initiatingMessage){ //Check Initiating Message
        InitiatingMessage_t* initiatingMessage = PDU->choice.initiatingMessage;
        if (initiatingMessage->procedureCode == ProcedureCode_id_RICindication && initiatingMessage->value.present == InitiatingMessage__value_PR_RICindication){ //Check RIC Indication
            RICindication_t *indication = &initiatingMessage->value.choice.RICindication;
            
            RICIndication *RicIndication = (RICIndication *)malloc(sizeof(RICIndication));
            if(PDU == NULL){
                fprintf(stderr, "Failed to allocate memory for RICIndication\n");
                return NULL;
            }

            for (int i = 0; i < indication->protocolIEs.list.count; i++ ){ //Mapping id to the corresponding protocol IE
                switch (indication->protocolIEs.list.array[i]->id){ //Refer to ProtocolIE-ID.h
                case ProtocolIE_ID_id_RICrequestID:{
                    RicIndication->RequestorID = indication->protocolIEs.list.array[i]->value.choice.RICrequestID.ricRequestorID;
                    RicIndication->RequestInstanceID = indication->protocolIEs.list.array[i]->value.choice.RICrequestID.ricInstanceID;
                    break;
                }
                case ProtocolIE_ID_id_RANfunctionID:{
                    RicIndication->RanfunctionID = indication->protocolIEs.list.array[i]->value.choice.RANfunctionID;
                    break;
                }
                case ProtocolIE_ID_id_RICactionID:{
                    RicIndication->ActionID = indication->protocolIEs.list.array[i]->value.choice.RICactionID;          
                    break;
                }
                case ProtocolIE_ID_id_RICindicationSN:{
                    RicIndication->IndicationSN = indication->protocolIEs.list.array[i]->value.choice.RICindicationSN;
                    break;
                }
                case ProtocolIE_ID_id_RICindicationType:{
                    RicIndication->IndicationType = indication->protocolIEs.list.array[i]->value.choice.RICindicationType;
                    break;
                }
                case ProtocolIE_ID_id_RICindicationHeader:{
                    size_t IndicationHeaderSize = indication->protocolIEs.list.array[i]->value.choice.RICindicationHeader.size;
                    
                    RicIndication->IndicationHeader = (uint8_t*)malloc(IndicationHeaderSize);
                    if(RicIndication->IndicationHeader == NULL){
                        fprintf(stderr, "Failed to allocate memory for RICIndicationHeader\n");
                        Free_RIC_Indication(RicIndication);
                        ASN_STRUCT_FREE(asn_DEF_E2AP_PDU, PDU);
                        return NULL;
                    }else{
                        memcpy(RicIndication->IndicationHeader, indication->protocolIEs.list.array[i]->value.choice.RICindicationHeader.buf, IndicationHeaderSize);
                        RicIndication->IndicationHeaderSize = IndicationHeaderSize;
                    }

                    break;
                }
                case ProtocolIE_ID_id_RICindicationMessage:{
                    size_t IndicationMessageSize = indication->protocolIEs.list.array[i]->value.choice.RICindicationMessage.size;

                    RicIndication->IndicationMessage = (uint8_t*)malloc(IndicationMessageSize);
                    if(RicIndication->IndicationMessage == NULL){
                        fprintf(stderr, "Failed to allocate memory for RICIndicationMessage\n");
                        Free_RIC_Indication(RicIndication);
                        ASN_STRUCT_FREE(asn_DEF_E2AP_PDU, PDU);
                        return NULL;
                    }else{
                        memcpy(RicIndication->IndicationMessage, indication->protocolIEs.list.array[i]->value.choice.RICindicationMessage.buf, IndicationMessageSize);
                        RicIndication->IndicationMessageSize = IndicationMessageSize;
                    }

                    break;
                } 
                case ProtocolIE_ID_id_RICcallProcessID:{
                    size_t CallProcessIDSize = indication->protocolIEs.list.array[i]->value.choice.RICcallProcessID.size;
                    
                    RicIndication->CallProcessID = (uint8_t*)malloc(CallProcessIDSize);
                    if(RicIndication->CallProcessID == NULL){
                        fprintf(stderr, "Failed to allocate memory for CallProcessID\n");
                        Free_RIC_Indication(RicIndication);
                        ASN_STRUCT_FREE(asn_DEF_E2AP_PDU, PDU);
                        return NULL;
                    }else{
                        memcpy(RicIndication->CallProcessID, indication->protocolIEs.list.array[i]->value.choice.RICcallProcessID.buf, CallProcessIDSize);
                        RicIndication->CallProcessIDSize = CallProcessIDSize;
                    }

                    break;
                }
                default:
                    break;
                }
            }
            return RicIndication;
        }
    }

    if(PDU != NULL) 
        ASN_STRUCT_FREE(asn_DEF_E2AP_PDU, PDU);
    return NULL;

}

void Free_RIC_Indication(RICIndication* RicIndication){
    if(RicIndication == NULL) {
        return;
    }
    else{
        if(RicIndication->IndicationHeader != NULL) {
            free(RicIndication->IndicationHeader);
            RicIndication->IndicationHeader = NULL;
        }

        if(RicIndication->IndicationMessage != NULL) {
            free(RicIndication->IndicationMessage);
            RicIndication->IndicationMessage = NULL;
        }

        if(RicIndication->CallProcessID != NULL) {
            //free(RicIndication->CallProcessID);
            RicIndication->CallProcessID = NULL;
        }
        free(RicIndication);
        RicIndication = NULL;
    }
    
}

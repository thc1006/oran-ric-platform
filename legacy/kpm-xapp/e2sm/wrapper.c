#include <errno.h>
#include "wrapper.h"

E2SM_KPM_RANfunction_Description_t *Decode_RAN_Function_Description(void *Buffer, size_t Buf_Size, int AsnPrint_Flag){
    asn_dec_rval_t Result;
    E2SM_KPM_RANfunction_Description_t *RAN_Function_Description = (E2SM_KPM_RANfunction_Description_t*)calloc(1, sizeof(E2SM_KPM_RANfunction_Description_t));
    Result = aper_decode_complete(NULL, &asn_DEF_E2SM_KPM_RANfunction_Description, (void **)&RAN_Function_Description, Buffer, Buf_Size);
    if(Result.code == RC_OK){
        if(AsnPrint_Flag == 1){
            xer_fprint(stderr,  &asn_DEF_E2SM_KPM_RANfunction_Description, RAN_Function_Description);
        }
        return RAN_Function_Description;
    }else{
        ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_RANfunction_Description, RAN_Function_Description);
        return NULL;
    }
}

void Free_RAN_Function_Dscription(E2SM_KPM_RANfunction_Description_t *RAN_Function_Description){
    ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_RANfunction_Description, RAN_Function_Description);
}

ssize_t Encode_Event_Trigger_Definition(void *Buffer, size_t Buf_Size, long Report_Period, int AsnPrint_Flag){
    E2SM_KPM_EventTriggerDefinition_t *Event_Trigger_Definition = (E2SM_KPM_EventTriggerDefinition_t *)malloc(sizeof(E2SM_KPM_EventTriggerDefinition_t));
    if(!Event_Trigger_Definition){
        fprintf(stderr,"Failed to allocate memory for E2SM_KPM_EventTriggerDefinition_t\n") ;
        return -1;
    }

    E2SM_KPM_EventTriggerDefinition_Format1_t *Format1 = (E2SM_KPM_EventTriggerDefinition_Format1_t *)malloc(sizeof(E2SM_KPM_EventTriggerDefinition_Format1_t));
    if(!Format1){
        fprintf(stderr,"Failed to allocate memory for E2SM_KPM_EventTriggerDefinition_Format1_t\n") ;
        return -1;
    }
    Format1->reportingPeriod = Report_Period;

    Event_Trigger_Definition->eventDefinition_formats.present = E2SM_KPM_EventTriggerDefinition__eventDefinition_formats_PR_eventDefinition_Format1;
    Event_Trigger_Definition->eventDefinition_formats.choice.eventDefinition_Format1 = Format1;

    if(AsnPrint_Flag == 1){
        xer_fprint(stderr,  &asn_DEF_E2SM_KPM_EventTriggerDefinition, Event_Trigger_Definition);
    }

    asn_enc_rval_t Result;
    Result = aper_encode_to_buffer(&asn_DEF_E2SM_KPM_EventTriggerDefinition, NULL, Event_Trigger_Definition, Buffer, Buf_Size);

    if(Result.encoded == -1) {
        fprintf(stderr, "Can't encode %s: %s\n", Result.failed_type->name, strerror(errno));
        return -1;
    } else {
        return Result.encoded;
    }

}


E2SM_KPM_IndicationHeader_t *Decode_Indication_Header(void *Buffer, size_t Buf_Size, int AsnPrint_Flag){
    asn_dec_rval_t Result;
    E2SM_KPM_IndicationHeader_t *Indication_Header = (E2SM_KPM_IndicationHeader_t*)calloc(1, sizeof(E2SM_KPM_IndicationHeader_t));
    Result = aper_decode_complete(NULL, &asn_DEF_E2SM_KPM_IndicationHeader, (void **)&Indication_Header, Buffer, Buf_Size);
    if(Result.code == RC_OK){
        if(AsnPrint_Flag == 1){
            xer_fprint(stderr,  &asn_DEF_E2SM_KPM_IndicationHeader, Indication_Header);
        }
        return Indication_Header;
    }else{
        ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationHeader, Indication_Header);
        return NULL;
    }

}

void Free_Indication_Header(E2SM_KPM_IndicationHeader_t *Indication_Header){
    ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationHeader, Indication_Header);
}

E2SM_KPM_IndicationMessage_t *Decode_Indication_Message(void *Buffer, size_t Buf_Size, int AsnPrint_Flag){
    asn_dec_rval_t Result;
    E2SM_KPM_IndicationMessage_t *Indication_Message = (E2SM_KPM_IndicationMessage_t*)calloc(1, sizeof(E2SM_KPM_IndicationMessage_t));
    Result = aper_decode_complete(NULL, &asn_DEF_E2SM_KPM_IndicationMessage, (void **)&Indication_Message, Buffer, Buf_Size);
    if(Result.code == RC_OK){
        if(AsnPrint_Flag == 1){
            xer_fprint(stderr,  &asn_DEF_E2SM_KPM_IndicationMessage, Indication_Message);
        }
        return Indication_Message;
    }else{
        printf("Failed to decode element %d\n", Result.consumed);
        ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationMessage, Indication_Message);
        return NULL;
    }
}

void Free_Indication_Message(E2SM_KPM_IndicationMessage_t *Indication_Message){
    ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationMessage, Indication_Message);
}

ssize_t Encode_Indication_Header(void *Buffer, size_t Buf_Size, E2SM_KPM_IndicationHeader_t* IndicationHeader, int AsnPrint_Flag){
    if(AsnPrint_Flag == 1){
            xer_fprint(stderr,  &asn_DEF_E2SM_KPM_IndicationHeader, IndicationHeader);
    }
    
    asn_enc_rval_t Result;
    Result = aper_encode_to_buffer(&asn_DEF_E2SM_KPM_IndicationHeader, NULL, IndicationHeader, Buffer, Buf_Size);

    if(Result.encoded == -1) {
        fprintf(stderr, "Can't encode %s: %s\n", Result.failed_type->name, strerror(errno));
        return -1;
    } else {
        return Result.encoded;
    }
}

uint8_t fillBitString(BIT_STRING_t *id, uint8_t unusedBits, uint8_t byteSize, uint64_t data)
{
   uint64_t tmp = 0;
   uint8_t byteIdx = 0;

   if(id->buf == NULL)
   {
      return 1;
   }
   memset(id->buf, 0, byteSize);
   data = data << unusedBits;
   
   /*Now, seggregate the value into 'byteSize' number of Octets in sequence:
    * 1. Pull out a byte of value (Starting from MSB) and put in the 0th Octet
    * 2. Fill the buffer/String Octet one by one until LSB is reached*/
   for(byteIdx = 1; byteIdx <= byteSize; byteIdx++)
   {
      tmp = (uint64_t)0xFF;
      tmp = (tmp << (8 * (byteSize - byteIdx)));
      tmp = (data & tmp) >> (8 * (byteSize - byteIdx));
      id->buf[byteIdx - 1]  = tmp;
   }
   id->bits_unused = unusedBits;
   return 0;
}


ssize_t Encode_Action_Definition_Format_1_in_C(void *Buffer, size_t Buf_Size, void *measName, void *measNameLen, size_t sizeOfMeasName){
    // fprintf(stderr, "[Wrapper.c] INFO --> Jacky, Enter %s\n", __func__);

    // uint8_t cellID[] = "000100100011010001010110000000000001";
    uint8_t plmnID[] = {0x00, 0x1F, 0x01};
    char (*measNamePtr)[30] = (char (*)[30])measName;
    int *measNameLenPtr = (int*)measNameLen;
    
    E2SM_KPM_ActionDefinition_t *actionDefini;
    actionDefini = (E2SM_KPM_ActionDefinition_t *)calloc(1, sizeof(E2SM_KPM_ActionDefinition_t));
    E2SM_KPM_ActionDefinition_Format1_t *actionDefiniFmt1;
    actionDefiniFmt1 = (E2SM_KPM_ActionDefinition_Format1_t *)calloc(1, sizeof(E2SM_KPM_ActionDefinition_Format1_t));
    MeasurementInfoItem_t *measInfoItem = (MeasurementInfoItem_t*)calloc(sizeOfMeasName, sizeof(MeasurementInfoItem_t));
    LabelInfoItem_t *labelInfoItem = (LabelInfoItem_t*)calloc(sizeOfMeasName, sizeof(LabelInfoItem_t));
    CGI_t *cgi = (CGI_t*)calloc(1, sizeof(CGI_t));
    NR_CGI_t *nrcgi = (NR_CGI_t*)calloc(1, sizeof(NR_CGI_t));
    nrcgi->pLMNIdentity.buf = (uint8_t*)calloc(3, sizeof(uint8_t));
    nrcgi->nRCellIdentity.buf = (uint8_t*)calloc(5, sizeof(uint8_t));
    nrcgi->nRCellIdentity.size = 5;
    nrcgi->nRCellIdentity.bits_unused = 4;

    if(!actionDefini){
        fprintf(stderr,"Failed to allocate memory for E2SM_KPM_ActionDefinition_t\n") ;
        return -1;
    }

    actionDefini->ric_Style_Type = 1;
    actionDefini->actionDefinition_formats.present = E2SM_KPM_ActionDefinition__actionDefinition_formats_PR_actionDefinition_Format1;
    actionDefini->actionDefinition_formats.choice.actionDefinition_Format1 = actionDefiniFmt1;
    actionDefiniFmt1->granulPeriod = 10000;
    actionDefiniFmt1->cellGlobalID = cgi;

    cgi->present = CGI_PR_nR_CGI;
    cgi->choice.nR_CGI = nrcgi;
    fillBitString(&nrcgi->nRCellIdentity, 4, 5, 0b000100100011010001010110000000000001);

    nrcgi->pLMNIdentity.size = 3;
    memcpy(nrcgi->pLMNIdentity.buf, plmnID, 3);
    
    for(int i=0;i<sizeOfMeasName;i++){
        measInfoItem[i].measType.present = MeasurementType_PR_measName;
        measInfoItem[i].measType.choice.measName.size = measNameLenPtr[i];
        measInfoItem[i].measType.choice.measName.buf = (uint8_t*)calloc(measNameLenPtr[i], sizeof(uint8_t));
        memcpy(measInfoItem[i].measType.choice.measName.buf, measNamePtr[i], measNameLenPtr[i]);
        labelInfoItem[i].measLabel.noLabel = (long*)calloc(1, sizeof(long));
        *labelInfoItem[i].measLabel.noLabel = MeasurementLabel__noLabel_true;
        ASN_SEQUENCE_ADD(&measInfoItem[i].labelInfoList.list, &labelInfoItem[i]);
        ASN_SEQUENCE_ADD(&actionDefiniFmt1->measInfoList.list, &measInfoItem[i]);

    }

    xer_fprint(stderr,  &asn_DEF_E2SM_KPM_ActionDefinition, actionDefini);

    asn_enc_rval_t Result;
    Result = aper_encode_to_buffer(&asn_DEF_E2SM_KPM_ActionDefinition, NULL, actionDefini, Buffer, Buf_Size);

    if(Result.encoded == -1) {
        fprintf(stderr, "Can't encode %s: %s\n", Result.failed_type->name, strerror(errno));
        return -1;
    } else {
        return Result.encoded;
    }

    return 0;
}


/*
ssize_t Encode_Action_Definition_Format_1_in_C(void *Buffer, size_t Buf_Size, void *measName, void *measNameLen, size_t sizeOfMeasName){
    // fprintf(stderr, "[Wrapper.c] INFO --> Jacky, Enter %s\n", __func__);

    // uint8_t cellID[] = "000100100011010001010110000000000001";
    uint8_t plmnID[] = {0x00, 0x1F, 0x01};
    char (*measNamePtr)[30] = (char (*)[30])measName;
    int *measNameLenPtr = (int*)measNameLen;
    
    E2SM_KPM_ActionDefinition_t *actionDefini;
    actionDefini = (E2SM_KPM_ActionDefinition_t *)calloc(1, sizeof(E2SM_KPM_ActionDefinition_t));
    E2SM_KPM_ActionDefinition_Format1_t *actionDefiniFmt1;
    actionDefiniFmt1 = (E2SM_KPM_ActionDefinition_Format1_t *)calloc(1, sizeof(E2SM_KPM_ActionDefinition_Format1_t));
    MeasurementInfoItem_t *measInfoItem = (MeasurementInfoItem_t*)calloc(sizeOfMeasName, sizeof(MeasurementInfoItem_t));
    LabelInfoItem_t *labelInfoItem = (LabelInfoItem_t*)calloc(sizeOfMeasName, sizeof(LabelInfoItem_t));
    CGI_t *cgi = (CGI_t*)calloc(1, sizeof(CGI_t));
    NR_CGI_t *nrcgi = (NR_CGI_t*)calloc(1, sizeof(NR_CGI_t));
    nrcgi->pLMNIdentity.buf = (uint8_t*)calloc(3, sizeof(uint8_t));
    nrcgi->nRCellIdentity.buf = (uint8_t*)calloc(5, sizeof(uint8_t));
    nrcgi->nRCellIdentity.size = 5;
    nrcgi->nRCellIdentity.bits_unused = 4;

    if(!actionDefini){
        fprintf(stderr,"Failed to allocate memory for E2SM_KPM_ActionDefinition_t\n") ;
        return -1;
    }

    actionDefini->ric_Style_Type = 1;
    actionDefini->actionDefinition_formats.present = E2SM_KPM_ActionDefinition__actionDefinition_formats_PR_actionDefinition_Format1;
    actionDefini->actionDefinition_formats.choice.actionDefinition_Format1 = actionDefiniFmt1;
    actionDefiniFmt1->granulPeriod = 10000;
    actionDefiniFmt1->cellGlobalID = cgi;

    cgi->present = CGI_PR_nR_CGI;
    cgi->choice.nR_CGI = nrcgi;
    fillBitString(&nrcgi->nRCellIdentity, 4, 5, 0b000100100011010001010110000000000001);

    nrcgi->pLMNIdentity.size = 3;
    memcpy(nrcgi->pLMNIdentity.buf, plmnID, 3);
    
    for(int i=0;i<sizeOfMeasName;i++){
        measInfoItem[i].measType.present = MeasurementType_PR_measName;
        measInfoItem[i].measType.choice.measName.size = measNameLenPtr[i];
        measInfoItem[i].measType.choice.measName.buf = (uint8_t*)calloc(measNameLenPtr[i], sizeof(uint8_t));
        memcpy(measInfoItem[i].measType.choice.measName.buf, measNamePtr[i], measNameLenPtr[i]);
        labelInfoItem[i].measLabel.noLabel = (long*)calloc(1, sizeof(long));
        *labelInfoItem[i].measLabel.noLabel = MeasurementLabel__noLabel_true;
        ASN_SEQUENCE_ADD(&measInfoItem[i].labelInfoList.list, &labelInfoItem[i]);
        ASN_SEQUENCE_ADD(&actionDefiniFmt1->measInfoList.list, &measInfoItem[i]);

    }

    xer_fprint(stderr,  &asn_DEF_E2SM_KPM_ActionDefinition, actionDefini);

    asn_enc_rval_t Result;
    Result = aper_encode_to_buffer(&asn_DEF_E2SM_KPM_ActionDefinition, NULL, actionDefini, Buffer, Buf_Size);

    if(Result.encoded == -1) {
        fprintf(stderr, "Can't encode %s: %s\n", Result.failed_type->name, strerror(errno));
        return -1;
    } else {
        return Result.encoded;
    }

    return 0;
}
*/

ssize_t Encode_Action_Definition_Format_3_in_C(void *Buffer, size_t Buf_Size, void *measName, void *measNameLen, size_t sizeOfMeasName){
    uint8_t plmnID[] = {0x00, 0x1F, 0x01};
    char (*measNamePtr)[25] = (char (*)[25])measName;
    int *measNameLenPtr = (int*)measNameLen;
    
    E2SM_KPM_ActionDefinition_t *actionDefini;
    actionDefini = (E2SM_KPM_ActionDefinition_t *)calloc(1, sizeof(E2SM_KPM_ActionDefinition_t));
    E2SM_KPM_ActionDefinition_Format3_t *actionDefiniFmt3;
    actionDefiniFmt3 = (E2SM_KPM_ActionDefinition_Format3_t *)calloc(1, sizeof(E2SM_KPM_ActionDefinition_Format3_t));
    MeasurementCondItem_t *measCondItem = (MeasurementCondItem_t*)calloc(sizeOfMeasName, sizeof(MeasurementCondItem_t));
    MeasurementLabel_t *measLabel = (MeasurementLabel_t*)calloc(sizeOfMeasName, sizeof(MeasurementLabel_t));
    MatchingCondItem_t *matchingCondItem = (MatchingCondItem_t*)calloc(sizeOfMeasName, sizeof(MatchingCondItem_t));
    CGI_t *cgi = (CGI_t*)calloc(1, sizeof(CGI_t));
    NR_CGI_t *nrcgi = (NR_CGI_t*)calloc(1, sizeof(NR_CGI_t));
    nrcgi->pLMNIdentity.buf = (uint8_t*)calloc(3, sizeof(uint8_t)); // Fixed length: 36
    nrcgi->nRCellIdentity.buf = (uint8_t*)calloc(5, sizeof(uint8_t));
    nrcgi->nRCellIdentity.size = 5;
    nrcgi->nRCellIdentity.bits_unused = 4;

    if(!actionDefini){
        fprintf(stderr,"Failed to allocate memory for E2SM_KPM_ActionDefinition_t\n") ;
        return -1;
    }

    actionDefini->ric_Style_Type = 3;
    actionDefini->actionDefinition_formats.present = E2SM_KPM_ActionDefinition__actionDefinition_formats_PR_actionDefinition_Format3;
    actionDefini->actionDefinition_formats.choice.actionDefinition_Format3 = actionDefiniFmt3;
    actionDefiniFmt3->granulPeriod = 1;
    actionDefiniFmt3->cellGlobalID = cgi;

    cgi->present = CGI_PR_nR_CGI;
    cgi->choice.nR_CGI = nrcgi;
    fillBitString(&nrcgi->nRCellIdentity, 4, 5, 0b000100100011010001010110000000000001);

    nrcgi->pLMNIdentity.size = 3;
    memcpy(nrcgi->pLMNIdentity.buf, plmnID, 3);
    
    for(int i=0;i<sizeOfMeasName;i++){
        measCondItem[i].measType.present = MeasurementType_PR_measName;
        measCondItem[i].measType.choice.measName.size = measNameLenPtr[i];
        measCondItem[i].measType.choice.measName.buf = (uint8_t*)calloc(measNameLenPtr[i], sizeof(uint8_t));
        memcpy(measCondItem[i].measType.choice.measName.buf, measNamePtr[i], measNameLenPtr[i]);
        
        matchingCondItem[i].matchingCondChoice.present = MatchingCondItem_Choice_PR_measLabel;
        matchingCondItem[i].matchingCondChoice.choice.measLabel = &measLabel[i];
        measLabel[i].noLabel = (long*)calloc(1, sizeof(long));
        *measLabel[i].noLabel = MeasurementLabel__noLabel_true;
        ASN_SEQUENCE_ADD(&measCondItem[i].matchingCond.list, &matchingCondItem[i]);
        ASN_SEQUENCE_ADD(&actionDefiniFmt3->measCondList.list, &measCondItem[i]);
    }

    xer_fprint(stderr,  &asn_DEF_E2SM_KPM_ActionDefinition, actionDefini);

    asn_enc_rval_t Result;
    Result = aper_encode_to_buffer(&asn_DEF_E2SM_KPM_ActionDefinition, NULL, actionDefini, Buffer, Buf_Size);

    if(Result.encoded == -1) {
        fprintf(stderr, "Can't encode %s: %s\n", Result.failed_type->name, strerror(errno));
        return -1;
    } else {
        return Result.encoded;
    }

    return 0;
}

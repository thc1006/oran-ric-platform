#ifndef _WRAPPER_H_
#define _WRAPPER_H_

//Include Libraries
# include "E2SM-KPM-RANfunction-Description.h"

# include "E2SM-KPM-EventTriggerDefinition.h"
# include "E2SM-KPM-EventTriggerDefinition-Format1.h"

# include "E2SM-KPM-ActionDefinition.h"
# include "E2SM-KPM-ActionDefinition-Format1.h"
# include "E2SM-KPM-ActionDefinition-Format2.h"
# include "E2SM-KPM-ActionDefinition-Format3.h"
# include "E2SM-KPM-ActionDefinition-Format4.h"
# include "E2SM-KPM-ActionDefinition-Format5.h"


# include "E2SM-KPM-IndicationHeader.h"
# include "E2SM-KPM-IndicationHeader-Format1.h"
# include "E2SM-KPM-IndicationMessage.h"
# include "E2SM-KPM-IndicationMessage-Format1.h"
# include "E2SM-KPM-IndicationMessage-Format2.h"
# include "E2SM-KPM-IndicationMessage-Format3.h"

# include "MeasurementInfoItem.h"
# include "MeasurementInfoList.h"
# include "MeasurementTypeName.h"
# include "MeasurementTypeID.h"
# include "MeasurementCondItem.h"
# include "MeasurementCondList.h"
# include "MeasurementTypeID.h"
# include "MeasurementLabel.h"

# include "MatchingCondList.h"
# include "MatchingCondItem.h"
# include "MatchingUEidList.h"
# include "MatchingUeCondPerSubList.h"
# include "MatchingUeCondPerSubItem.h"
# include "MatchingUEidPerSubItem.h"

# include "LabelInfoItem.h"
# include "CGI.h"
# include "PLMNIdentity.h"
# include "NRCellIdentity.h"
# include "EUTRACellIdentity.h"
# include "NR-CGI.h"
# include "EUTRA-CGI.h"

# include "TestCondInfo.h"
# include "TestCond-Value.h"
# include "GranularityPeriod.h"
# include "UEID.h"

# include "GlobalGNB-ID.h"
# include "GlobalNgENB-ID.h"
# include "GlobalNGRANNodeID.h"
# include "MatchingUEidItem.h"
# include "MeasurementCondUEidItem.h"
# include "MeasurementDataItem.h"
# include "MeasurementInfo-Action-Item.h"
# include "MeasurementRecordItem.h"
# include "RIC-EventTriggerStyle-Item.h"
# include "RIC-ReportStyle-Item.h"
# include "S-NSSAI.h"
# include "NULL.h"
# include "UEID-GNB-CU-CP-E1AP-ID-Item.h"
# include "UEID-GNB-CU-CP-E1AP-ID-List.h"
# include "UEID-GNB-CU-CP-F1AP-ID-Item.h"
# include "UEID-GNB-CU-F1AP-ID-List.h"
# include "UEID-GNB-CU-UP.h"
# include "UEID-GNB-DU.h"
# include "UEID-GNB.h"
# include "UEMeasurementReportItem.h"



#ifdef __cplusplus
extern "C" {
#endif

//Function Definition
E2SM_KPM_RANfunction_Description_t *Decode_RAN_Function_Description(void *Buffer, size_t Buf_Size, int AsnPrint_Flag);
void Free_RAN_Function_Dscription(E2SM_KPM_RANfunction_Description_t *RAN_Function_Description);

ssize_t Encode_Event_Trigger_Definition(void *Buffer, size_t Buf_Size, long Report_Period, int AsnPrint_Flag);

E2SM_KPM_IndicationHeader_t *Decode_Indication_Header(void *Buffer, size_t Buf_Size, int AsnPrint_Flag);
void Free_Indication_Header(E2SM_KPM_IndicationHeader_t *Indication_Header);

E2SM_KPM_IndicationMessage_t *Decode_Indication_Message(void *Buffer, size_t Buf_Size, int AsnPrint_Flag);
void Free_Indication_Message(E2SM_KPM_IndicationMessage_t *Indication_Message);

ssize_t Encode_Indication_Header(void *Buffer, size_t Buf_Size, E2SM_KPM_IndicationHeader_t* IndicationHeader, int AsnPrint_Flag);

uint8_t fillBitString(BIT_STRING_t *id, uint8_t unusedBits, uint8_t byteSize, uint64_t data);
ssize_t Encode_Action_Definition_Format_1_in_C(void *Buffer, size_t Buf_Size, void *measName, void *measNameLen, size_t sizeOfMeasName);
ssize_t Encode_Action_Definition_Format_3_in_C(void *Buffer, size_t Buf_Size, void *measName, void *measNameLen, size_t sizeOfMeasName);

#ifdef __cplusplus
}
#endif

#endif
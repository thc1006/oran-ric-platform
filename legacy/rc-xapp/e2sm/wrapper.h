#ifndef _WRAPPER_H_
#define _WRAPPER_H_

#include "BOOLEAN.h"
#include "NativeReal.h"
#include "REAL.h"
#include "OCTET_STRING.h"
#include "E2SM-RC-ControlHeader-Format1.h"
#include "E2SM-RC-ControlHeader.h"
#include "E2SM-RC-ControlMessage-Format1.h"
#include "E2SM-RC-ControlMessage.h"
#include "E2SM-RC-RANFunctionDefinition.h"
#include "INTEGER.h"
#include "NativeInteger.h"
#include "OPEN_TYPE.h"
#include "PrintableString.h"
#include "RANParameter-ID.h"
#include "RANParameter-LIST.h"
#include "RANParameter-Name.h"
#include "RANParameter-STRUCTURE.h"
#include "RANParameter-Value.h"
#include "RANParameter-ValueType.h"
#include "RANfunction-Name.h"
#include "RIC-ControlAction-ID.h"
#include "RIC-ControlAction-Name.h"
#include "RIC-Format-Type.h"
#include "RIC-Style-Name.h"
#include "RIC-Style-Type.h"
#include "RANParameter-ValueType-Choice-ElementFalse.h"
#include "RANParameter-ValueType-Choice-Structure.h"
#include "RANParameter-ValueType-Choice-List.h"
#include "UEID.h"
#include "UEID-GNB-DU.h"
#include "UEID-GNB.h"
#include "UEID-GNB-CU-F1AP-ID-List.h"
#include "UEID-GNB-CU-CP-E1AP-ID-List.h"
#include "UEID-GNB-CU-CP-F1AP-ID-Item.h"
#include "UEID-GNB-CU-CP-E1AP-ID-Item.h"
#include "E2SM-RC-ControlMessage-Format1-Item.h"
#include "RANParameter-STRUCTURE-Item.h"
#include "E2SM-RC-ControlOutcome.h"
#include "E2SM-RC-ControlOutcome-Format1.h"
#include "E2SM-RC-ControlOutcome-Format1-Item.h"
#include "NR-CGI.h"


long    F1AP_id[1];
long    E1AP_id[1];
struct uEID {
    long    amf_UE_NGAP_Id;
    //size_t  amf_UE_NGAP_Id_size;
    const char* pLMNIdentity;
    size_t  pLMNIdentity_size;
    const char* aMFRegionID;
    size_t  aMFRegionID_size;
    const char* aMFSetID;
    size_t  aMFSetID_size;
    const char* aMFPointer;
    size_t  aMFPointer_size;
};


extern ssize_t e2sm_encode_ric_control_header(void *buffer, size_t buf_size,struct uEID *in,long f1AP[],size_t f1AP_len,long e1AP[],size_t e1Ap_len,long ricControlStyleType, long ricControlActionID, void *ranParameterValue, size_t ranParameterValue_size);

extern ssize_t e2sm_encode_ric_control_message(void *buffer, size_t buf_size, long targetPrimaryCell, long targetCell, long nrOrEUtraCell, long nrCGIOrECGI, void *ranParameterValue,  size_t  ranParameterValue_size);

extern E2SM_RC_ControlOutcome_t* e2sm_decode_ric_call_process_outcome(void *buffer, size_t buf_size);
extern void e2sm_free_ric_call_process_outcome(E2SM_RC_ControlOutcome_t* controlOutcome) ;
extern ssize_t e2sm_encode_nrcgi(NR_CGI_t *nr_cgi, void* ranParameterValue, size_t ranParameterValue_size,
                ulong lNRCellId,uint8_t* buffer, size_t buf_size);

extern int fillListInformat1Item(E2SM_RC_ControlMessage_Format1_Item_t *format1_item, int id, RANParameter_LIST_t *src_list);
extern int fillListInStruct(RANParameter_STRUCTURE_Item_t *struct_item, int id, RANParameter_LIST_t *src_list);
extern int fillStructInStruct(RANParameter_STRUCTURE_Item_t *struct_item, int id, RANParameter_STRUCTURE_t *src_struct);
extern int fillRanParaValueInt(RANParameter_STRUCTURE_Item_t *struct_item, int id, int value); 
extern int fillRanParaValueOctet(RANParameter_STRUCTURE_Item_t *struct_item, int id, void* ranParameterValue, size_t ranParameterValue_size);
//extern ssize_t encode_slice_level_quote(void *buffer, size_t buf_size, void* sst, size_t sst_size, void *sd, size_t sd_size, int min, int max, int ded);
 
ssize_t encode_slice_level_quote(void *buffer, size_t buf_size, int policyNum, void *memberNum_ptr, void *plmnId_ptr, void *sst_ptr, void *sd_ptr, void *min_ptr, void *max_ptr, void *ded_ptr);

ssize_t encode_slice_level_header(void *buffer, size_t buf_size, long ricControlStyleType, long ricControlActionID);


#endif /* _WRAPPER_H_ */

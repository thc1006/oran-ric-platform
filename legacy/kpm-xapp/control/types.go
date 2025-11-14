package control

/*E2SM-KPMv2 Structure*/
type E2SM_KPM_RANfunction_Description struct {
	ranFunction_Name           RANfunction_Name
	ric_EventTriggerStyle_List []RIC_EventTriggerStyle_Item
	ric_ReportStyle_List       []RIC_ReportStyle_Item
}

type RANfunction_Name struct {
	ranFunction_ShortName   PrintableString
	ranFunction_E2SM_OID    PrintableString
	ranFunction_Description PrintableString
	ranFunction_Instance    *int64
}

type RIC_EventTriggerStyle_Item struct {
	ric_EventTriggerStyle_Type  int64           //RIC_Style_Type
	ric_EventTriggerStyle_Name  PrintableString //RIC_Style_Name
	ric_EventTriggerFormat_Type int64           //RIC_Format_Type
}

type RIC_ReportStyle_Item struct {
	ric_ReportStyle_Type             int64           //RIC_Style_Type
	ric_ReportStyle_Name             PrintableString //RIC_Style_Name
	ric_ActionFormat_Type            int64           //RIC_Format_Type
	measInfo_Action_List             []MeasurementInfo_Action_Item
	ric_IndicationHeaderFormat_Type  int64 //RIC_Format_Type
	ric_IndicationMessageFormat_Type int64 //RIC_Format_Type
}

type MeasurementInfo_Action_Item struct {
	measName PrintableString
	measID   *int64 // Optional
}

type MeasurementInfoItem struct { //Choose One
	measType      interface{}
	labelInfoList []LabelInfoItem
}
type measName PrintableString
type measID int64

type LabelInfoItem MeasurementLabel

type MeasurementLabel struct { //Must contain 1 item
	noLabel          *int64       /* OPTIONAL */ // nolabel = 0 means true
	plmnID           *OctetString /* OPTIONAL */
	sliceID          *S_NSSAI     /* OPTIONAL */
	fiveQI           *int64       /* OPTIONAL */
	qFI              *int64       /* OPTIONAL */
	qCI              *int64       /* OPTIONAL */
	qCImax           *int64       /* OPTIONAL */
	qCImin           *int64       /* OPTIONAL */
	aRPmax           *int64       /* OPTIONAL */
	aRPmin           *int64       /* OPTIONAL */
	bitrateRange     *int64       /* OPTIONAL */
	layerMU_MIMO     *int64       /* OPTIONAL */
	sUM              *int64       /* OPTIONAL */
	distBinX         *int64       /* OPTIONAL */
	distBinY         *int64       /* OPTIONAL */
	distBinZ         *int64       /* OPTIONAL */
	preLabelOverride *int64       /* OPTIONAL */
	startEndInd      *int64       /* OPTIONAL */
	min              *int64       /* OPTIONAL */
	max              *int64       /* OPTIONAL */
	avg              *int64       /* OPTIONAL */
}

type S_NSSAI struct {
	sST OctetString
	sD  *OctetString /* OPTIONAL */
}

type E2SM_KPM_ActionDefinition_Format1 struct {
	measInfoList []MeasurementInfoItem
	granulPeriod uint64
	cellGlobalID *CGI /* OPTIONAL */
}

type E2SM_KPM_ActionDefinition_Format3 struct {
	measCondList []MeasurementCondItem
	granulPeriod uint64
	cellGlobalID *CGI /* OPTIONAL */
}

type CGI struct {
	pLMNIdentity string
	CellIdentity string
	NodebType    int //1: eNB, 2: gNB
}

type MeasurementCondItem struct {
	measType     interface{} // Choose one
	matchingCond []MatchingCondItem
}

type MatchingCondItem interface{} //Chooes one
type measLabel MeasurementLabel
type testCondInfo TestCondInfo

type TestCondInfo struct {
	testType  int64
	testExpr  interface{}
	testValue TestCond_Value
}

type TestCond_Value interface{} // Choose One
type valueInt int64
type valueEnum int64
type valueBool Boolean
type valueBitS BitString
type valueOctS OctetString
type valuePrtS PrintableString

type E2SM_KPM_IndicationHeader struct { //Choose One
	indicationHeader_FormatType int32
	indicationHeader_Format     interface{}
}

type E2SM_KPM_IndicationHeader_Format1 struct {
	colletStartTime   OctetString
	fileFormatversion *string /* OPTIONAL */
	senderName        *string /* OPTIONAL */
	senderType        *string /* OPTIONAL */
	vendorName        *string /* OPTIONAL */
}

type E2SM_KPM_IndicationMessage struct { //Choose One
	indicationMessage_FormatsType int32
	indicationMessage_Formats     interface{}
}
type indicationMessage_Format1 E2SM_KPM_IndicationMessage_Format1
type indicationMessage_Format2 E2SM_KPM_IndicationMessage_Format2
type indicationMessage_Format3 E2SM_KPM_IndicationMessage_Format3

type E2SM_KPM_IndicationMessage_Format1 struct {
	measData     []MeasurementDataItem
	measInfoList *[]MeasurementInfoItem /* OPTIONAL */
	granulPeriod *uint64                /* OPTIONAL */
}

type MeasurementDataItem struct {
	measRecord     []MeasurementRecordItem
	incompleteFlag *int64 /* OPTIONAL */
}

type MeasurementRecordItem interface{} //Choose One
type integer uint64
type real float64 // Note: Type Conversion
type noValue int32

type E2SM_KPM_IndicationMessage_Format2 struct {
	measData         []MeasurementDataItem
	measCondUEidList MeasurementCondUEidList
	granulPeriod     *uint64 /* OPTIONAL */
}

type MeasurementCondUEidList []MeasurementCondUEidItem

type MeasurementCondUEidItem struct {
	measType         interface{}
	matchingCond     []MatchingCondItem
	matchingUEidList *[]MatchingUEidItem /* OPTIONAL */
}

// Influx DB Structure

type Timestamp struct {
	TVsec  int64 `json:"tv_sec"`
	TVnsec int64 `json:"tv_nsec"`
}

/*
type CellMetricsEntry struct {
	MeasTimestampPDCPBytes Timestamp `json:"MeasTimestampPDCPBytes"`
	CellID 		       string 	 `json:"CellID"`
	PDCPBytesDL            int64     `json:"PDCPBytesDL"`
	PDCPBytesUL            int64     `json:"PDCPBytesUL"`
	MeasTimestampPRB       Timestamp `json:"MeasTimestampAvailPRB"`
	AvailPRBDL             int64     `json:"AvailPRBDL"`
	AvailPRBUL             int64     `json:"AvailPRBUL"`
	MeasPeriodPDCP	       int64	 `json:"MeasPeriodPDCPBytes"`
	MeasPeriodPRB	       int64	 `json:"MeasPeriodAvailPRB"`
}
*/

type CellRFType struct {
	RSRP   int `json:"rsrp"`
	RSRQ   int `json:"rsrq"`
	RSSINR int `json:"rssinr"`
}

type NeighborCellRFType struct {
	CellID string     `json:"CID"`
	CellRF CellRFType `json:"CellRF"`
}

/*
type UeMetricsEntry struct {
	UeID                   int64     `json:"UEID"`
	ServingCellID          string    `json:"ServingCellID"`
	MeasTimestampPDCPBytes Timestamp `json:"MeasTimestampUEPDCPBytes"`
	PDCPBytesDL            int64     `json:"UEPDCPBytesDL"`
	PDCPBytesUL            int64     `json:"UEPDCPBytesUL"`
	MeasTimestampPRB       Timestamp `json:"MeasTimestampUEPRBUsage"`
	PRBUsageDL             int64     `json:"UEPRBUsageDL"`
	PRBUsageUL             int64     `json:"UEPRBUsageUL"`
	MeasTimeRF             Timestamp `json:"MeasTimestampRF"`
	MeasPeriodRF	       int64	 `json:"MeasPeriodRF"`
	MeasPeriodPDCP	       int64	 `json:"MeasPeriodUEPDCPBytes"`
	MeasPeriodPRB	       int64	 `json:"MeasPeriodUEPRBUsage"`
	ServingCellRF   CellRFType           `json:"ServingCellRF"`
	NeighborCellsRF []NeighborCellRFType `json:"NeighborCellRF"`
}
*/

type CellMetricsEntry struct {
	RanName        string  `json:"RanName"`
	DRB_UEThpDl    int     `json:"DRB.UEThpDl"`
	RRU_PrbUsedDl  int     `json:"RRU.PrbUsedDl"`
	RRU_PrbAvailDl int     `json:"RRU.PrbAvailDl"`
	RRU_PrbTotDl   float64 `json:"RRU.PrbTotDl"`
}

type SliceMetricsEntry struct {
	RanName       string `json:"RanName"`
	SliceID       string `json:"SliceID"`
	DRB_UEThpDl   int    `json:"DRB.UEThpDl.SNSSAI"`
	RRU_PrbUsedDl int    `json:"RRU.PrbUsedDl.SNSSAI"`
}

//type MatchingUEidList []MatchingUEidItem

type MatchingUEidItem struct {
	ueID UEID
}

type UEID interface{} //Choose One
type gNB_UEID UEID_GNB
type gNB_DU_UEID UEID_GNB_DU
type gNB_CU_UP_UEID UEID_GNB_CU_UP
type ng_eNB_UEID UEID_NG_ENB
type ng_eNB_DU_UEID UEID_NG_ENB_DU
type en_gNB_UEID UEID_EN_GNB
type eNB_UEID UEID_ENB

type UEID_GNB struct {
	amf_UE_NGAP_ID            Integer
	guami                     GUAMI
	gNB_CU_UE_F1AP_ID_List    *[]UEID_GNB_CU_CP_F1AP_ID_Item /* OPTIONAL */
	gNB_CU_CP_UE_E1AP_ID_List *[]UEID_GNB_CU_CP_E1AP_ID_Item /* OPTIONAL */
	ran_UEID                  *OctetString                   /* OPTIONAL */
	m_NG_RAN_UE_XnAP_ID       *uint64                        /* OPTIONAL */
	globalGNB_ID              *GlobalGNB_ID                  /* OPTIONAL */
	globalNG_RANNode_ID       *interface{}                   /* OPTIONAL */
}

type GUAMI struct {
	pLMNIdentity OctetString
	aMFRegionID  BitString
	aMFSetID     BitString
	aMFPointer   BitString
}

type UEID_GNB_CU_F1AP_ID_List []UEID_GNB_CU_CP_F1AP_ID_Item

type UEID_GNB_CU_CP_F1AP_ID_Item struct {
	gNB_CU_UE_F1AP_ID uint64
}

//type GNB_CU_UE_F1AP_ID uint64

type UEID_GNB_CU_CP_E1AP_ID_List []UEID_GNB_CU_CP_E1AP_ID_Item

type UEID_GNB_CU_CP_E1AP_ID_Item struct {
	gNB_CU_CP_UE_E1AP_ID uint64
}

type GlobalGNB_ID struct {
	pLMNIdentity OctetString
	gNB_ID       interface{} //Choose One
}
type GNB_ID struct {
	gNB_ID BitString
}

type GlobalNGRANNodeID interface{} //Chooes One
type gNB GlobalGNB_ID
type ng_eNB GlobalNgENB_ID

type GlobalNgENB_ID struct {
	pLMNIdentity OctetString
	ngENB_ID     NgENB_ID
}

type NgENB_ID interface{} // Choose One
type macroNgENB_ID BitString
type shortMacroNgENB_ID BitString
type longMacroNgENB_ID BitString

type UEID_GNB_DU struct {
	gNB_CU_UE_F1AP_ID uint64
	ran_UEID          *OctetString /* OPTIONAL */
}

type UEID_GNB_CU_UP struct {
	gNB_CU_CP_UE_E1AP_ID uint64
	ran_UEID             *OctetString /* OPTIONAL */
}

type UEID_NG_ENB struct {
	amf_UE_NGAP_ID       Integer
	guami                GUAMI
	ng_eNB_CU_UE_W1AP_ID *uint64         /* OPTIONAL */
	m_NG_RAN_UE_XnAP_ID  *uint64         /* OPTIONAL */
	globalNgENB_ID       *GlobalNgENB_ID /* OPTIONAL */
}

type UEID_NG_ENB_DU struct {
	ng_eNB_CU_UE_W1AP_ID uint64
}

type UEID_EN_GNB struct {
	m_eNB_UE_X2AP_ID           int64
	m_eNB_UE_X2AP_ID_Extension *int64 /* OPTIONAL */
	globalENB_ID               GlobalENB_ID
	gNB_CU_UE_F1AP_ID          *uint64                      /* OPTIONAL */
	gNB_CU_CP_UE_E1AP_ID_List  *UEID_GNB_CU_CP_E1AP_ID_List /* OPTIONAL */
	ran_UEID                   *OctetString                 /* OPTIONAL */
}

type GlobalENB_ID struct {
	pLMNIdentity OctetString
	eNB_ID       ENB_ID
}

type ENB_ID interface{} //Choose
type macro_eNB_ID BitString
type home_eNB_ID BitString
type short_Macro_eNB_ID BitString
type long_Macro_eNB_ID BitString

type UEID_ENB struct {
	mME_UE_S1AP_ID             uint64
	gUMMEI                     GUMMEI
	m_eNB_UE_X2AP_ID           *int64        /* OPTIONAL */
	m_eNB_UE_X2AP_ID_Extension *int64        /* OPTIONAL */
	globalENB_ID               *GlobalENB_ID /* OPTIONAL */
}

type GUMMEI struct {
	pLMN_Identity OctetString
	mME_Group_ID  OctetString
	mME_Code      OctetString
}

type E2SM_KPM_IndicationMessage_Format3 struct {
	ueMeasReportList []UEMeasurementReportItem
}

type UEMeasurementReportItem struct {
	ueID       UEID
	measReport E2SM_KPM_IndicationMessage_Format1
}

/*E2APv2 Structure*/
type RICIndication struct {
	RequestorID           int32
	RequestInstanceID     int32
	RanfunctionID         int32
	ActionID              int32
	IndicationSN          int32 /*Optional*/
	IndicationType        int32
	IndicationHeader      []byte
	IndicationHeaderSize  int32
	IndicationMessage     []byte
	IndicationMessageSize int32
	CallProcessID         []byte /*Optional*/
	CallProcessIDSize     int32  /*Optional*/
}

/*ASN.1 Structure*/
type PrintableString OctetString

type Integer OctetString

type Boolean int32

type OctetString struct {
	Buf  []byte
	Size int
}

type BitString struct {
	Buf        []byte
	Size       int
	BitsUnused int
}

package control

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"reflect"
	"strconv"
	"strings"
	"time"

	"gerrit.o-ran-sc.org/r/ric-plt/xapp-frame/pkg/xapp"
	influxdb2 "github.com/influxdata/influxdb-client-go"
	"github.com/influxdata/influxdb-client-go/api/write"
	"github.com/spf13/viper"
)

// Define the struct for the JSON response
type Result struct {
	Results []struct {
		StatementID int `json:"statement_id"`
		Series      []struct {
			Name    string          `json:"name"`
			Columns []string        `json:"columns"`
			Values  [][]interface{} `json:"values"`
		} `json:"series"`
	} `json:"results"`
}

var (
	cellMetricsInfo  []string
	sliceMetricsInfo []string
	cellSubMetrics []string
	sliceSubMetrics []string
	userName = "admin"
	password = "WKgvgGt5ni"
)

type Control struct {
	e2IfState    *E2IfState
	client       influxdb2.Client //client for influxdb
	cellMetrics  []string
	sliceMetrics []string
}

func (c *Control) HandleSubscription(RanName string, RanFunId int64, RanfunctionDefinition *E2SM_KPM_RANfunction_Description) {
	SubscriptionRequestPayload, err := GenerateSubscriptionRequestPayload(RanName, RanFunId, RanfunctionDefinition)
	if err != nil {
		xapp.Logger.Error("Failed to generate subscription request payload for Ran name: %s, error: %v", RanName, err)
	} else {
		for _, item := range SubscriptionRequestPayload {
			SubscriptionResponse, err := xapp.Subscription.Subscribe(item)
			if err != nil {
				xapp.Logger.Error("Failed to send subscription request for Ran name: %s, error: %v", RanName, err)
			} else {
				xapp.Logger.Debug("Subscription Response Payload: %+v", SubscriptionResponse)
			}
		}
	}
}

func writeFieldValue(name string, value interface{}, structPtr interface{}) error {
	structValue := reflect.ValueOf(structPtr).Elem()
	structFieldType := structValue.Type()

	// Loop over the fields of the struct and check if the name matches the one we want to set.
	for i := 0; i < structValue.NumField(); i++ {
		field := structValue.Field(i)
		if strings.EqualFold(structFieldType.Field(i).Name, name) {
			// The name matches, so set the value of the field using reflection.
			if !field.CanSet() {
				return fmt.Errorf("cannot set value of field %q", name)
			}
			switch v := value.(type) {
			case int:
				field.SetInt(int64(v))
			case uint64:
				field.SetInt(int64(v))
			case float64:
				field.SetFloat(float64(v))
			default:
				return fmt.Errorf("unsupported type %T for field %q", value, name)
			}
			return nil
		}
	}
	// The field was not found in the struct.
	return fmt.Errorf("field %q not found in struct", name)
}

func AddItemToBeginningOfStringSlice(slice []string, item string) []string {
	newSlice := make([]string, len(slice)+1)
	newSlice[0] = item
	copy(newSlice[1:], slice)
	return newSlice
}

func (c *Control) writeInfluxDB(msg *xapp.RMRParams, IndicationMessage *E2SM_KPM_IndicationMessage) (err error) {

	cellMetricsName := AddItemToBeginningOfStringSlice(cellMetricsInfo, "RanName")
	sliceMetricsName := AddItemToBeginningOfStringSlice(sliceMetricsInfo, "SliceID")
	sliceMetricsName = AddItemToBeginningOfStringSlice(sliceMetricsName, "RanName")

	// difference := FindArrayDifference(cellMetricsName, cellMetricsInfo)
	// xapp.Logger.Debug("Cell Metrics %v", cellMetricsName)

	// difference1 := FindArrayDifference(sliceMetricsName, sliceMetricsInfo)
	// xapp.Logger.Debug("Slice Metrics %v", sliceMetricsName)

	// xapp.Logger.Debug("writeInfluxDB: Ran Name is: %s", msg.Meid.RanName)
	switch IndicationMessage.indicationMessage_FormatsType {
	case 1:
		var cellMetrics CellMetricsEntry
		cellMetrics.RanName = msg.Meid.RanName
		var measDataItem []MeasurementDataItem
		var measInfoList []MeasurementInfoItem

		IndiMsgFmt1 := IndicationMessage.indicationMessage_Formats.(*E2SM_KPM_IndicationMessage_Format1)
		measDataItem = IndiMsgFmt1.measData

		var measNameList []string
		var cellValueList []interface{}

		if IndiMsgFmt1.measInfoList != nil {
			measInfoList = (*IndiMsgFmt1.measInfoList)
			for _, item := range measInfoList {
				switch v := item.measType.(type) {
				case PrintableString: // meas Name
					// Handle case where the record is an unsigned integer
					// xapp.Logger.Debug("Measurement Name is: %s", v.Buf)
					measNameList = append(measNameList, string(v.Buf))
				case int64: // meas ID
					xapp.Logger.Debug("Measurement ID is: %d", v)
					measNameList = append(measNameList, strconv.FormatInt(v, 10))
				default:
					xapp.Logger.Debug("Invaild measurement type")
					// Handle other cases as necessary
				}
			}
		}

		for _, item := range measDataItem {
			// Access fields of the item as necessary
			measRecordList := item.measRecord

			// Iterate over the list of measurement record items
			for _, record := range measRecordList {
				// Access fields of the record as necessary
				switch v := record.(type) {
				case uint64:
					// Handle case where the record is an unsigned integer
					// xapp.Logger.Debug("Integer measurement field: %d", int(v))
					cellValueList = append(cellValueList, int32(v))
				case float64:
					// Handle case where the record is a floating-point number
					// xapp.Logger.Debug("Float measurement field: %2f", v)
					cellValueList = append(cellValueList, v)
				case int32:
					// Handle case where the record has no value
					xapp.Logger.Debug("No Value field")
				default:
					// Handle other cases as necessary
				}
			}
		}

		if len(measNameList) == 0{
			measNameList = cellSubMetrics
		}

		if len(cellValueList) != len(measNameList) {
			xapp.Logger.Debug("Record size isn't equivalent: %d, %d", len(cellValueList), len(measNameList))
		} else {
			writeAPI := c.client.WriteAPIBlocking("my-org", "kpm")
			p := influxdb2.NewPointWithMeasurement("CellMetrics").
				AddTag("RanName", cellMetrics.RanName).
				SetTime(time.Now())
			for i, item := range measNameList {
				index := -1
				for j, val := range cellMetricsName {
					if val == item {
						index = j
						break
					}
				}

				if index == -1 {
					xapp.Logger.Debug("Cell Metrics Name isn't found, %v", item)
				} else {
					p = p.AddField(cellMetricsName[index], cellValueList[i])
					// xapp.Logger.Debug("Fill in field: ", reflect.ValueOf(cellMetrics).Type().Field(index).Name, cellValueList[i])
					// err := writeFieldValue(reflect.ValueOf(cellMetrics).Type().Field(index).Name, cellValueList[i], &cellMetrics)
					// if err != nil {
					// 	xapp.Logger.Debug("writeFieldValue failed, reason: ", err)
					// }

				}
			}
			err := writeAPI.WritePoint(context.Background(), p)
			if err != nil {
				xapp.Logger.Debug("WritePoint failed, reason: ", err)
			} else {
				str := "Wrote cell metrics: " 
				for _, item := range p.TagList() {
					str = str + fmt.Sprintf("%s = %v, ", item.Key, item.Value)
				}

				for i, item := range p.FieldList() {
					if i == 0 {
						str = str + fmt.Sprintf("%s = %v", item.Key, item.Value)
					}else{
						str = str + fmt.Sprintf(", %s = %v", item.Key, item.Value)
					} 
				}
				xapp.Logger.Debug("%v", str)
			}
			// c.writeCellMetrics_db(cellMetrics)
		}

	case 2:
		var sliceMetrics []SliceMetricsEntry
		// sliceMetrics.RanName = msg.Meid.RanName
		// sliceMetrics.SliceID = "01020304"
		var measDataItem []MeasurementDataItem
		var measCondUEidList []MeasurementCondUEidItem
		var measNameList []string
		var sliceIdList []string
		var sliceValueList []interface{}

		IndiMsgFmt2 := IndicationMessage.indicationMessage_Formats.(*E2SM_KPM_IndicationMessage_Format2)
		measDataItem = IndiMsgFmt2.measData
		measCondUEidList = IndiMsgFmt2.measCondUEidList

		for _, item := range measCondUEidList {
			switch v := item.measType.(type) {
			case PrintableString: // meas Name
				// Handle case where the record is an unsigned integer
				// xapp.Logger.Debug("Measurement Name is: %s", v.Buf)
				measNameList = append(measNameList, string(v.Buf))
			case int64: // meas ID
				// xapp.Logger.Debug("Measurement ID is: %d", v)
				measNameList = append(measNameList, strconv.FormatInt(v, 10))
			default:
				xapp.Logger.Debug("Invaild measurement type")
				// Handle other cases as necessary
			}

			for _, condItem := range item.matchingCond {
				switch w := condItem.(type) {
				case MeasurementLabel:
					if w.sliceID != nil {
						var sliceId string
						sst := w.sliceID.sST.Buf

						if w.sliceID.sD != nil {
							sd := w.sliceID.sD.Buf
							sliceId = hex.EncodeToString(sst) + hex.EncodeToString(sd)
						} else {
							sliceId = hex.EncodeToString(sst)
						}
						sliceIdList = append(sliceIdList, sliceId)
						// xapp.Logger.Debug("Slice ID is %s", sliceId)
					} else {
						xapp.Logger.Debug("Measurement Label isn't supported")
					}
				default:
					xapp.Logger.Debug("condItem type is invaild")
				}

			}
		}

		for _, item := range measDataItem {
			// Access fields of the item as necessary
			measRecordList := item.measRecord

			// Iterate over the list of measurement record items
			for _, record := range measRecordList {
				// Access fields of the record as necessary
				switch v := record.(type) {
				case uint64:
					// Handle case where the record is an unsigned integer
					// xapp.Logger.Debug("Integer measurement field: ", v)
					sliceValueList = append(sliceValueList, int32(v))
				case float64:
					// Handle case where the record is a floating-point number
					// xapp.Logger.Debug("Float measurement field: %2f", v)
					sliceValueList = append(sliceValueList, v)
				case int32:
					// Handle case where the record has no value
					xapp.Logger.Debug("No Value field")
				default:
					// Handle other cases as necessary
				}
			}
		}

		// xapp.Logger.Debug("SliceValueList:", sliceValueList)

		// Remove duplicated slice ID
		unique := make(map[string]bool)
		for _, val := range sliceIdList {
			unique[val] = true
		}
		uniqueSliceId := make([]string, 0, len(unique))
		for key := range unique {
			uniqueSliceId = append(uniqueSliceId, key)
		}

		sliceMetrics = make([]SliceMetricsEntry, len(uniqueSliceId))
		for i := range sliceMetrics {
			sliceMetrics[i].RanName = msg.Meid.RanName
			sliceMetrics[i].SliceID = uniqueSliceId[i]
		}

		if len(measNameList) == 0{
			measNameList = sliceSubMetrics
		}

		if len(sliceValueList) != len(measNameList) {
			xapp.Logger.Debug("Record size isn't equivalent: %d, %d", len(sliceValueList), len(measNameList))
		} else {
			var points []*write.Point
			writeAPI := c.client.WriteAPIBlocking("my-org", "kpm")

			for i := 0; i < len(unique); i++ {
				points = append(points, influxdb2.NewPointWithMeasurement("SliceMetrics").
					AddTag("RanName", sliceMetrics[i].RanName).
					AddTag("SliceID", sliceMetrics[i].SliceID).
					SetTime(time.Now()))
			}

			for i, item := range measNameList {
				nameIndex := -1
				for j, val := range sliceMetricsName {
					if val == item {
						nameIndex = j
						break
					}
				}

				sliceIdIndex := -1
				for j, val := range uniqueSliceId {
					if val == sliceIdList[i] {
						sliceIdIndex = j
						break
					}
				}

				if nameIndex == -1 {
					xapp.Logger.Debug("Slice Metrics Name isn't found, %v", item)
				} else if sliceIdIndex == -1 {
					xapp.Logger.Debug("Slice ID isn't found, %v", item)
				} else {
					points[sliceIdIndex] = points[sliceIdIndex].AddField(sliceMetricsName[nameIndex], sliceValueList[i])
					// writeFieldValue(reflect.ValueOf(sliceMetrics[sliceIdIndex]).Type().Field(nameIndex).Name, sliceValueList[i], &sliceMetrics[sliceIdIndex])

				}
			}

			for i, p := range points {
				err := writeAPI.WritePoint(context.Background(), p)
				if err != nil {
					xapp.Logger.Debug("WritePoint failed, reason: ", err)
				} else {
					str := "Wrote slice #" + strconv.Itoa(i)  + " metrics: " 
					for _, item := range p.TagList() {
						str = str + fmt.Sprintf("%s = %v, ", item.Key, item.Value)
					}
	
					for j, item := range p.FieldList() {
						if j==0 {
							str = str + fmt.Sprintf("%s = %v", item.Key, item.Value)
						}else{
							str = str + fmt.Sprintf(", %s = %v", item.Key, item.Value)
						} 
					}
					xapp.Logger.Debug("%v", str)

				}
			}

			// for _, item := range sliceMetrics {
			// 	c.writeSliceMetrics_db(item)
			// }
		}

	default:
		xapp.Logger.Debug("Invaild message format type %d", IndicationMessage.indicationMessage_FormatsType)
	}

	return
}

func (c *Control) HandleIndication(msg *xapp.RMRParams) (err error) {
	// Check gNB Exist

	// Using E2AP to decode RIC Indication
	xapp.Logger.Debug("RIC Indication Payload:", msg.Payload)

	e2ap := &E2ap{}
	Indication, err := e2ap.RICIndicationDecode(msg.Payload)
	if err != nil {
		xapp.Logger.Error("Failed to decode RIC Indication: %v", err)
		return
	}

	xapp.Logger.Debug("Successfully decode RIC Indication sent by gNB: %s", msg.Meid.RanName)
	xapp.Logger.Debug("Got RIC Indication Header Payload:", Indication.IndicationHeader, len(Indication.IndicationHeader))
	xapp.Logger.Debug("Got RIC Indication Message Payload:", Indication.IndicationMessage, len(Indication.IndicationMessage))
	// Check Action Type

	// Using E2SM-KPM to decode RIC Indication Header
	e2sm := &E2sm{}
	IndicationHeader, err := e2sm.IndicationHeaderDecode(Indication.IndicationHeader)
	if err != nil {
		xapp.Logger.Error("Failed to decode RIC Indication Header: %v", err)
		//return
	}

	xapp.Logger.Debug("Successfully decode Indication Header with E2SM-KPM, got header format type %d", IndicationHeader.indicationHeader_FormatType)

	// Using E2SM-KPM to decode RIC Indication Message
	IndicationMessage, err := e2sm.IndicationMessageDecode(Indication.IndicationMessage)
	if err != nil {
		xapp.Logger.Error("Failed to decode RIC Indication Message: %v", err)
		//return
	}

	xapp.Logger.Debug("Successfully decode Indication Message with E2SM-KPM, got message format type %d", IndicationMessage.indicationMessage_FormatsType)

	c.writeInfluxDB(msg, IndicationMessage)

	// Store into InfluxDB

	return
}

func (c *Control) RMRMessageHandler(msg *xapp.RMRParams) {

	xapp.Logger.Debug("Message received: name=%d meid=%s subId=%d txid=%s len=%d", msg.Mtype, msg.Meid.RanName, msg.SubId, msg.Xid, msg.PayloadLen)

	switch msg.Mtype {
	// RIC_INDICATION
	case 12050:
		xapp.Logger.Info("Received RIC Indication")
		go c.HandleIndication(msg)

	// health check request
	case 100:
		xapp.Logger.Info("Received health check request")

	// unknown Message
	default:
		xapp.Logger.Warn("Unknown message type '%d', discarding", msg.Mtype)
	}
	defer func() { //After processing, we need to free the Mbuf
		xapp.Rmr.Free(msg.Mbuf)
		msg.Mbuf = nil
	}()

}

func (c *Control) Consume(msg *xapp.RMRParams) (err error) {
	c.RMRMessageHandler(msg)
	return
}

func (c *Control) xAppStartCB(d interface{}) {
	//After rigistration complete, start to initiate the other functions.
	xapp.Logger.Info("xApp ready call back received")

	//Initiate E2IfState
	c.e2IfState.Init(c)
}

func (c *Control) Run() {
	//Set Logger Configuration
	xappname := viper.GetString("name")
	xappversion := viper.GetString("version")
	xapp.Logger.SetMdc("Name", xappname)
	xapp.Logger.SetMdc("Version", xappversion)

	//When xApp is ready, it will reveive Callback
	xapp.SetReadyCB(c.xAppStartCB, true)

	//Register REST Subscription Call Back
	xapp.Subscription.SetResponseCB(SubscriptionResponseCallback)

	xapp.Run(c)
}

func (c *Control) writeCellMetrics_db(cellMetrics CellMetricsEntry) {
	//Write cell metrics to InfluxDB using API
	// username := "admin"
	// password := "UwuVmf6Tha"
	writeAPI := c.client.WriteAPIBlocking("my-org", "kpm")
	cellMetricsJSON, er := json.Marshal(cellMetrics)
	if er != nil {
		xapp.Logger.Info("Marshal Cell Metrics failed!")
	} else {
		xapp.Logger.Info("Wrote Cell Metrics to InfluxDB, %s", cellMetricsJSON)
	}
	p := influxdb2.NewPointWithMeasurement("CellMetrics").
		AddField("RanName", cellMetrics.RanName).
		AddField("DRB.UEThpDl", cellMetrics.DRB_UEThpDl).
		AddField("RRU.PrbUsedDl", cellMetrics.RRU_PrbUsedDl).
		AddField("RRU.PrbAvailDl", cellMetrics.RRU_PrbAvailDl).
		AddField("RRU.PrbTotDl", cellMetrics.RRU_PrbTotDl).
		SetTime(time.Now())
	writeAPI.WritePoint(context.Background(), p)

}

func (c *Control) writeSliceMetrics_db(sliceMetrics SliceMetricsEntry) {
	//Write cell metrics to InfluxDB using API
	// username := "admin"
	// password := "UwuVmf6Tha"
	writeAPI := c.client.WriteAPIBlocking("my-org", "kpm")
	sliceMetricsJSON, er := json.Marshal(sliceMetrics)
	if er != nil {
		xapp.Logger.Info("Marshal Slice Metrics failed!")
	} else {
		xapp.Logger.Info("Wrote Slice Metrics to InfluxDB, %s", sliceMetricsJSON)
	}
	p := influxdb2.NewPointWithMeasurement("SliceMetrics").
		AddField("RanName", sliceMetrics.RanName).
		AddField("SliceID", sliceMetrics.SliceID).
		AddField("DRB.UEThpDl.SNSSAI", sliceMetrics.DRB_UEThpDl).
		AddField("RRU.PrbUsedDl.SNSSAI", sliceMetrics.RRU_PrbUsedDl).
		SetTime(time.Now())
	writeAPI.WritePoint(context.Background(), p)

}

func create_db() {
	//Create a database named kpimon in influxDB
	// username := "admin"
	// password := "UwuVmf6Tha"
	url := "http://ricplt-influxdb.ricplt:8086/query?q=create%20database%20kpm" + fmt.Sprintf("&u=%s&p=%s", userName, password)

	_, err := http.Post(url, "", nil)
	if err != nil {
		xapp.Logger.Info("Create database failed!")
	} else {
		xapp.Logger.Info("Create database successfully!")
	}
}

func getCellMetricsName() {
	// Send GET request
	url := "http://ricplt-influxdb.ricplt:8086/query?db=kpm&q=SELECT%20*%20FROM%20CellMetrics" + fmt.Sprintf("&u=%s&p=%s", userName, password)

	response, err := http.Get(url)
	if err != nil {
		xapp.Logger.Info("Error sending request:", err)
	}else{
		defer response.Body.Close()
	}

	// Read response body
	body, err := ioutil.ReadAll(response.Body)
	if err != nil {
		xapp.Logger.Info("Error reading response:", err)
	}

	// Parse the JSON response
	var data Result
	if err := json.Unmarshal(body, &data); err != nil {
		xapp.Logger.Info("Error parsing JSON:", err)
	}

	var columnNames []string

	// Extract the column names
	if len(data.Results) > 1{
		columnNames = data.Results[0].Series[0].Columns
	}else{
		columnNames = []string{"DRB.UEThpDl", "RRU.PrbUsedDl", "RRU.PrbAvailDl", "RRU.PrbTotDl"}
		// columnNames = []string{"DRB.UEThpDl", "DRB.UEThpUl", "PEE.AvgPower", "PEE.Energy",
		// "QosFlow.TotPdcpPduVolumeDl", "QosFlow.TotPdcpPduVolumeUl", "RRC.ConnMax"}
	}
	

	// Remove the "time" and "RanName" elements from the slice
	for _, col := range columnNames {
		if col != "time" && col != "RanName" {
			cellMetricsInfo = append(cellMetricsInfo, col)
		}
	}

	// Print the column names
	xapp.Logger.Info("cell Metrics Name: %v", cellMetricsInfo)
}

func getSliceMetricsName() {
	// Send GET request
	url := "http://ricplt-influxdb.ricplt:8086/query?db=kpm&q=SELECT%20*%20FROM%20SliceMetrics" + fmt.Sprintf("&u=%s&p=%s", userName, password)
	response, err := http.Get(url)
	if err != nil {
		xapp.Logger.Info("Error sending request:", err)
	}else{
		defer response.Body.Close()
	}

	// Read response body
	body, err := ioutil.ReadAll(response.Body)
	if err != nil {
		xapp.Logger.Info("Error reading response:", err)
	}

	// Parse the JSON response
	var data Result
	if err := json.Unmarshal(body, &data); err != nil {
		xapp.Logger.Info("Error parsing JSON:", err)
	}

	var columnNames []string

	// Extract the column names
	if len(data.Results) > 1{
		columnNames = data.Results[0].Series[0].Columns
	}else{
		columnNames = []string{"DRB.UEThpDl.SNSSAI", "RRU.PrbUsedDl.SNSSAI"}
	}
	

	// Remove the "time" and "RanName" elements from the slice
	for _, col := range columnNames {
		if col != "time" && col != "RanName" && col != "SliceID" {
			sliceMetricsInfo = append(sliceMetricsInfo, col)
		}
	}

	// Print the column names
	xapp.Logger.Info("Slice Metrics Name: %v", sliceMetricsInfo)
}

/*
func Init() {
	create_db()
	kpm := &Control{
		e2IfState: &E2IfState{},
		influxdb2.NewClient("http://ricplt-influxdb.ricplt:8086", "client"),
	}
	kpm.Run()
}
*/

func Init() {
	create_db()
	kpm := &Control{
		e2IfState:    &E2IfState{},
		client:       influxdb2.NewClient("http://ricplt-influxdb.ricplt:8086", fmt.Sprintf("%s:%s", userName, password)),
		cellMetrics:  cellMetricsInfo,
		sliceMetrics: sliceMetricsInfo,
	}
	getCellMetricsName()
	getSliceMetricsName()
	// client: influxdb2.NewClient("http://ricplt-influxdb.ricplt:8086", "client"),
	kpm.Run()
}

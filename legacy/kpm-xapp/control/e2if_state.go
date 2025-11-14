/*
==================================================================================
  Copyright (c) 2019 AT&T Intellectual Property.
  Copyright (c) 2019 Nokia

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
==================================================================================
*/
// Refer to submgr/e2if_state.go
package control

import (
	"fmt"
	"strings"
	"sync"

	"gerrit.o-ran-sc.org/r/ric-plt/xapp-frame/pkg/xapp"
)

type E2IfState struct {
	mutex   sync.Mutex
	control *Control
	NbIdMap map[string]int64 //Map [NbId] RanFinctionId, which indicates the RanfunctionId contains E2SM-KPMv2.
}

func (e *E2IfState) Init(c *Control) {
	e.control = c

	//Initiate Map
	e.NbIdMap = make(map[string]int64, 0)

	//Start to read Rnib for RAN
	e.ReadE2ConfigurationFromRnib()

	//Register to Sdl channel in order to be notified at the run time
	e.SubscribeSdlChannel()
}

func (e *E2IfState) GetAllE2Nodes() map[string]int64 {

	e.mutex.Lock()
	defer e.mutex.Unlock()
	return e.NbIdMap
}

func (e *E2IfState) SdlNotificationCb(ch string, events ...string) { //Refer to Subscription Manager
	//Handle Callback Event
	xapp.Logger.Debug("SDL notification received from channel=%s, event=%v", ch, events[0])
	if len(events) == 0 {
		xapp.Logger.Error("Invalid SDL notification received: %d", len(events))
		return
	}

	if strings.Contains(events[0], "_CONNECTED") && !strings.Contains(events[0], "_CONNECTED_SETUP_FAILED") {
		//Extract ran name from string, string example: "gnb_208_092_303030_CONNECTED"
		nbId, err := ExtractNbiIdFromString(events[0])
		if err != nil {
			xapp.Logger.Error("NotificationCb CONNECTED len(nbId) == 0 ")
			return
		}
		xapp.Logger.Debug("E2 CONNECTED. NbId=%s", nbId)

		//Check OID
		RanFunctionId, RanFunctionDefinition := e.GetRanFunctionDefinitionByOid(nbId)
		if RanFunctionDefinition == nil {
			xapp.Logger.Debug("Can't find E2SM-KPMv2 RanfunctionDefinition for %s", nbId)
			return
		}

		//Add to map
		e.NbIdMap[nbId] = RanFunctionId

		//Initiate Subscription Request Procedure
		go e.control.HandleSubscription(nbId, RanFunctionId, RanFunctionDefinition)

	} else if strings.Contains(events[0], "_DISCONNECTED") {
		nbId, err := ExtractNbiIdFromString(events[0])
		if err != nil {
			xapp.Logger.Error("NotificationCb DISCONNECTED len(nbId) == 0 ")
			return
		}
		xapp.Logger.Debug("E2 DISCONNECTED. NbId=%s", nbId)

		// Check map & Delete
		if _, ok := e.NbIdMap[nbId]; ok {
			delete(e.NbIdMap, nbId)
		}
	}
}

func (e *E2IfState) SubscribeSdlChannel() (err error) { //Refer to Subscription Manager
	//Register Sdl Callback and Check
	if err = xapp.Rnib.Subscribe(e.SdlNotificationCb, "RAN_CONNECTION_STATUS_CHANGE"); err != nil {
		xapp.Logger.Error("Sdl.SubscribeChannel failed: %v", err)
		return err
	}
	xapp.Logger.Debug("Subscription to RAN state changes done!")
	return nil
}

func (e *E2IfState) ReadE2ConfigurationFromRnib() {

	xapp.Logger.Debug("ReadE2ConfigurationFromRnib()")
	nbIdentities, err := xapp.Rnib.GetListGnbIds()
	if err != nil || len(nbIdentities) == 0 {
		xapp.Logger.Debug("There are no active NodeBs available: %v", err)
		e.NbIdMap = make(map[string]int64, 0)
		return
	}

	for _, nbIdentity := range nbIdentities {
		if e.isNodeBActive(nbIdentity.InventoryName) == false { //Disconnected
			if _, ok := e.NbIdMap[nbIdentity.InventoryName]; ok {
				delete(e.NbIdMap, nbIdentity.InventoryName)
				xapp.Logger.Debug("E2 connection DISCONNETED: %v", nbIdentity.InventoryName)

			}
			continue
		}

		if _, ok := e.NbIdMap[nbIdentity.InventoryName]; !ok {
			//Check OID
			RanFunctionId, RanFunctionDefinition := e.GetRanFunctionDefinitionByOid(nbIdentity.InventoryName)
			if RanFunctionDefinition == nil {
				xapp.Logger.Debug("Can't find E2SM-KPMv2 RanfunctionDefinition for %s", nbIdentity.InventoryName)
				return
			}

			//Add to map
			e.NbIdMap[nbIdentity.InventoryName] = RanFunctionId

			//Initiate Subscription Request Procedure
			go e.control.HandleSubscription(nbIdentity.InventoryName, RanFunctionId, RanFunctionDefinition)
		}
	}
}

func (e *E2IfState) isNodeBActive(inventoryName string) bool {
	nodeInfo, err := xapp.Rnib.GetNodeb(inventoryName)
	if err != nil {
		xapp.Logger.Error("GetNodeb() failed for inventoryName=%s: %v", inventoryName, err)
		return false
	}
	xapp.Logger.Debug("NodeB['%s'] connection status = %d", inventoryName, nodeInfo.ConnectionStatus)
	return nodeInfo.ConnectionStatus == 1
}

func ExtractNbiIdFromString(s string) (nbId string, err error) {

	// Expected string formats are below
	// gnb_208_092_303030_CONNECTED
	// gnb_208_092_303030_DISCONNECTED
	// ...

	if strings.Contains(s, "_CONNECTED") {
		splitStringTbl := strings.Split(s, "_CONNECTED")
		nbId = splitStringTbl[0]
	} else if strings.Contains(s, "_DISCONNECTED") {
		splitStringTbl := strings.Split(s, "_DISCONNECTED")
		nbId = splitStringTbl[0]
	}
	if len(nbId) == 0 {
		return "", fmt.Errorf("ExtractNbiIdFromString(): len(nbId) == 0 ")
	}
	return nbId, err
}

func (e *E2IfState) GetRanFunctionDefinitionByOid(NbId string) (int64, *E2SM_KPM_RANfunction_Description) {
	nodebInfor, err := xapp.Rnib.GetNodeb(NbId)
	if err != nil {
		xapp.Logger.Error("Failed to get NodebInfor for %s, error: %v", NbId, err)
	}
	xapp.Logger.Debug("nodebInfor is %v", nodebInfor)

	//Check gNB, NodeBType = 2 means gNB
	if nodebInfor.NodeType == 2 {
		RanFunctionList := nodebInfor.GetGnb().RanFunctions

		for i := 0; i < len(RanFunctionList); i++ {
			RANFunction := RanFunctionList[i]

			e2sm := &E2sm{}
			RanFunDef, err := e2sm.RanFunctionDefinitionDecode(RANFunction.RanFunctionDefinition)
			if err != nil {
				xapp.Logger.Warn("Failed to decode RAN Function Definition for NodeB Id %s, RanFunction Id = %d, err = %v", NbId, RANFunction.RanFunctionId, err)
			} else if string(RanFunDef.ranFunction_Name.ranFunction_E2SM_OID.Buf) == E2smKPMv3OId {
				xapp.Logger.Debug("NodeB Id %s, RanFunction Id = %d, support E2SM-KPMv3, OID = %s, Append NodeB Id", NbId, RANFunction.RanFunctionId, E2smKPMv3OId)
				return int64(RANFunction.RanFunctionId), RanFunDef
			} else {
				xapp.Logger.Debug("NodeB Id %s, RanFunction Id = %d, E2SM OID doesn't match, expected is %s, have %s", NbId, RANFunction.RanFunctionId, E2smKPMv3OId, err)
				xapp.Logger.Debug("NodeB Id %s, RanFunction Id = %d, E2SM OID is %s", NbId, RANFunction.RanFunctionId, RanFunDef.ranFunction_Name.ranFunction_E2SM_OID.Buf)
			}
		}

	} else {
		xapp.Logger.Debug("KPM xApp doesn't support eNB %s", nodebInfor.RanName)

	}
	return -1, nil
}

#./grpcurl -plaintext -d "{ \"e2NodeID\": \"36000000\", \"plmnID\": \"111\", \"ranName\": \"gnb_131_133_36000000\", \"RICE2APHeaderData\": { \"RanFuncId\": 300, \"RICRequestorID\": 2 }, \"RICControlHeaderData\": { \"ControlStyle\": 3, \"ControlActionId\": 1, \"UEID\": \"00006\" }, \"RICControlMessageData\": { \"RICControlCellTypeVal\": 4, \"TargetCellID\": \"1113\" }, \"RICControlAckReqVal\": 0 }"  10.96.106.3:7777 rc.MsgComm.SendRICControlReqServiceGrpc

#10.96.106.3:7777  is the grpc server ip and port
#Values of other parameters can be provided as shown above

./grpcurl -plaintext -d "{\"ranName\": \"gnb_311_048_0000000a\", \"rrmPolicy\": [{\"member\": [{\"plmnId\" : \"311480\", \"sst\" : \"01\", \"sd\" : \"020304\"}] , \"minPRB\" : 25, \"maxPRB\" : 85, \"dedPRB\" : 25} , {\"member\": [{\"plmnId\" : \"311480\", \"sst\" : \"02\", \"sd\" : \"030304\"}], \"minPRB\" : 35, \"maxPRB\" : 75, \"dedPRB\" : 25}, {\"member\": [{\"plmnId\" : \"311480\", \"sst\" : \"03\", \"sd\" : \"040304\"}], \"minPRB\" : 35, \"maxPRB\" : 80, \"dedPRB\" : 25}]}" 10.104.108.9:7777 rc.MsgComm.SendRRMPolicyServiceGrpc



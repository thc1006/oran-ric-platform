#./grpcurl -plaintext -d "{ \"e2NodeID\": \"36000000\", \"plmnID\": \"111\", \"ranName\": \"gnb_131_133_36000000\", \"RICE2APHeaderData\": { \"RanFuncId\": 300, \"RICRequestorID\": 2 }, \"RICControlHeaderData\": { \"ControlStyle\": 3, \"ControlActionId\": 1, \"UEID\": \"00006\" }, \"RICControlMessageData\": { \"RICControlCellTypeVal\": 4, \"TargetCellID\": \"1113\" }, \"RICControlAckReqVal\": 0 }"  10.96.106.3:7777 rc.MsgComm.SendRICControlReqServiceGrpc

#10.96.106.3:7777  is the grpc server ip and port
#Values of other parameters can be provided as shown above

#./grpcurl -plaintext -d "{\"ranName\": \"gnb_0015_110_123456\", \"rrmPolicy\": [{\"member\": [{\"plmnId\" : \"001f01\", \"sst\" : \"01\", \"sd\" : \"020304\"}] , \"minPRB\" : 5, \"maxPRB\" : 5, \"dedPRB\" : 5}]}" 10.105.118.148:7777 rc.MsgComm.SendRRMPolicyServiceGrpc

./grpcurl -plaintext -d "{\"ranName\": \"gnb_0015_110_123456\", \"rrmPolicy\": [{\"member\": [{\"plmnId\" : \"001f01\", \"sst\" : \"01\", \"sd\" : \"020304\"}] , \"minPRB\" : 20, \"maxPRB\" : 20, \"dedPRB\" : 20} , {\"member\": [{\"plmnId\" : \"001f01\", \"sst\" : \"02\", \"sd\" : \"030404\"}], \"minPRB\" : 20, \"maxPRB\" : 20, \"dedPRB\" : 20}]}"  10.98.193.61:7777 rc.MsgComm.SendRRMPolicyServiceGrpc

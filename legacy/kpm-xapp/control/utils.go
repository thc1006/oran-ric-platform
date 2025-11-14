package control

import (
	"encoding/binary"
	"strconv"
	"strings"
)

func ByteSlice2Int64(BS []byte) (I int64) {
	I = int64(binary.LittleEndian.Uint64(BS))
	return
}

func ByteSlice2Int64Slice(BS []byte) (IS []int64) {
	for i := 0; i < len(BS); i++ {
		I := int64(BS[i])
		IS = append(IS, I)
	}
	return
}

func ConvertStr2Byte(str string) (val []byte) {
	length := len(str)
	for i := 0; i < length/2; i++ {
		SubStr := str[2*i : 2*i+2]
		v, _ := strconv.ParseUint(SubStr, 16, 8)
		val = append(val, byte(v))
	}
	return
}

func AddDotBetween2Number(str string) (str1 string) {
	str1 = strings.Replace(str, " ", ", ", -1)
	return
}

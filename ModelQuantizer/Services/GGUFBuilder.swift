//
//  GGUFBuilder.swift
//  ModelQuantizer
//
//  GGUF file format builder for creating quantized model files.
//

import Foundation

/// Builder for creating GGUF (GGML Universal Format) files
public struct GGUFBuilder {
    public enum MetadataValue {
        case uint8(UInt8)
        case int8(Int8)
        case uint16(UInt16)
        case int16(Int16)
        case uint32(UInt32)
        case int32(Int32)
        case float32(Float)
        case uint64(UInt64)
        case int64(Int64)
        case float64(Double)
        case bool(Bool)
        case string(String)
        case array([MetadataValue])
    }
    
    private var metadata: [(String, MetadataValue)] = []
    private var tensors: [(name: String, shape: [UInt32], type: GGMLType, data: Data)] = []
    
    mutating func addMetadata(key: String, value: MetadataValue) {
        metadata.append((key, value))
    }
    
    mutating func addTensor(name: String, shape: [UInt32], dataType: GGMLType, data: Data) {
        tensors.append((name, shape, dataType, data))
    }
    
    func build() throws -> Data {
        var data = Data()
        
        // Magic number
        data.append(Data("GGUF".utf8))
        
        // Version (3 for latest GGUF)
        data.append(UInt32(3).littleEndianData)
        
        // Tensor count
        data.append(UInt64(tensors.count).littleEndianData)
        
        // Metadata count
        data.append(UInt64(metadata.count).littleEndianData)
        
        // Write metadata
        for (key, value) in metadata {
            // Key length and string
            data.append(UInt64(key.utf8.count).littleEndianData)
            data.append(Data(key.utf8))
            
            // Value type and data
            try appendMetadataValue(value, to: &data)
        }
        
        // Write tensor info into a temporary buffer so offsets are stable
        var tensorInfoData = Data()
        var tensorDataOffset = data.count + calculateTensorInfoSize()
        tensorDataOffset = ((tensorDataOffset + 31) / 32) * 32

        for tensor in tensors {
            tensorInfoData.append(UInt64(tensor.name.utf8.count).littleEndianData)
            tensorInfoData.append(Data(tensor.name.utf8))
            tensorInfoData.append(UInt32(tensor.shape.count).littleEndianData)

            for dim in tensor.shape {
                tensorInfoData.append(UInt64(dim).littleEndianData)
            }

            tensorInfoData.append(tensor.type.rawValue.littleEndianData)
            tensorInfoData.append(UInt64(tensorDataOffset).littleEndianData)

            tensorDataOffset += tensor.data.count
            tensorDataOffset = ((tensorDataOffset + 31) / 32) * 32
        }

        data.append(tensorInfoData)

        while data.count % 32 != 0 {
            data.append(0)
        }
        
        // Write tensor data
        for tensor in tensors {
            data.append(tensor.data)
            
            // Pad to 32-byte alignment
            while data.count % 32 != 0 {
                data.append(0)
            }
        }
        
        return data
    }
    
    private func calculateTensorInfoSize() -> Int {
        var size = 0
        for tensor in tensors {
            // Name length (8) + name + n_dims (4) + shape (8 * n_dims) + type (4) + offset (8)
            size += 8 + tensor.name.utf8.count + 4 + (8 * tensor.shape.count) + 4 + 8
        }
        return size
    }
    
    private func appendMetadataValue(_ value: MetadataValue, to data: inout Data) throws {
        switch value {
        case .uint8(let v):
            data.append(UInt32(0).littleEndianData)
            data.append(v)
            
        case .int8(let v):
            data.append(UInt32(1).littleEndianData)
            data.append(UInt8(bitPattern: v))
            
        case .uint16(let v):
            data.append(UInt32(2).littleEndianData)
            data.append(v.littleEndianData)
            
        case .int16(let v):
            data.append(UInt32(3).littleEndianData)
            data.append(UInt16(bitPattern: v).littleEndianData)
            
        case .uint32(let v):
            data.append(UInt32(4).littleEndianData)
            data.append(v.littleEndianData)
            
        case .int32(let v):
            data.append(UInt32(5).littleEndianData)
            data.append(UInt32(bitPattern: v).littleEndianData)
            
        case .float32(let v):
            data.append(UInt32(6).littleEndianData)
            var value = v
            data.append(Data(bytes: &value, count: MemoryLayout<Float>.size))
            
        case .uint64(let v):
            data.append(UInt32(10).littleEndianData)
            data.append(v.littleEndianData)
            
        case .int64(let v):
            data.append(UInt32(11).littleEndianData)
            data.append(UInt64(bitPattern: v).littleEndianData)
            
        case .float64(let v):
            data.append(UInt32(12).littleEndianData)
            var value = v
            data.append(Data(bytes: &value, count: MemoryLayout<Double>.size))
            
        case .bool(let v):
            data.append(UInt32(7).littleEndianData)
            data.append(v ? 1 : 0)
            
        case .string(let s):
            data.append(UInt32(8).littleEndianData)
            data.append(UInt64(s.utf8.count).littleEndianData)
            data.append(Data(s.utf8))
            
        case .array(let arr):
            data.append(UInt32(9).littleEndianData)
            // Element type (use first element's type)
            if let first = arr.first {
                let typeId = getMetadataTypeId(first)
                data.append(typeId.littleEndianData)
            } else {
                data.append(UInt32(0).littleEndianData)
            }
            // Array length
            data.append(UInt64(arr.count).littleEndianData)
            // Array elements
            for element in arr {
                try appendArrayElement(element, to: &data)
            }
        }
    }
    
    private func appendArrayElement(_ value: MetadataValue, to data: inout Data) throws {
        switch value {
        case .uint8(let v): data.append(v)
        case .int8(let v): data.append(UInt8(bitPattern: v))
        case .uint16(let v): data.append(v.littleEndianData)
        case .int16(let v): data.append(UInt16(bitPattern: v).littleEndianData)
        case .uint32(let v): data.append(v.littleEndianData)
        case .int32(let v): data.append(UInt32(bitPattern: v).littleEndianData)
        case .float32(let v):
            var value = v
            data.append(Data(bytes: &value, count: MemoryLayout<Float>.size))
        case .uint64(let v): data.append(v.littleEndianData)
        case .int64(let v): data.append(UInt64(bitPattern: v).littleEndianData)
        case .float64(let v):
            var value = v
            data.append(Data(bytes: &value, count: MemoryLayout<Double>.size))
        case .bool(let v): data.append(v ? 1 : 0)
        case .string(let s):
            data.append(UInt64(s.utf8.count).littleEndianData)
            data.append(Data(s.utf8))
        case .array:
            throw QuantizationError.invalidModelFormat // Nested arrays not supported
        }
    }
    
    private func getMetadataTypeId(_ value: MetadataValue) -> UInt32 {
        switch value {
        case .uint8: return 0
        case .int8: return 1
        case .uint16: return 2
        case .int16: return 3
        case .uint32: return 4
        case .int32: return 5
        case .float32: return 6
        case .bool: return 7
        case .string: return 8
        case .array: return 9
        case .uint64: return 10
        case .int64: return 11
        case .float64: return 12
        }
    }
}

// MARK: - Integer Extensions

extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}

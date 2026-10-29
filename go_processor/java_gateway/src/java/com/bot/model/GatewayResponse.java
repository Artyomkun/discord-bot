package com.bot.model;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public class GatewayResponse {
    private String requestId;
    private String status;
    private String message;
    private Map<String, Object> data;
    private Map<String, Object> metadata;
    private long timestamp;
    private long processingTimeMs;
    private String errorCode;
    private String errorDetails;

    public GatewayResponse() {
        this.requestId = UUID.randomUUID().toString();
        this.timestamp = System.currentTimeMillis();
        this.data = new HashMap<>();
        this.metadata = new HashMap<>();
    }

    public GatewayResponse(String status, String message) {
        this();
        this.status = status;
        this.message = message;
    }

    // Статические фабричные методы
    public static GatewayResponse success(String message) {
        return new GatewayResponse("success", message);
    }

    public static GatewayResponse success(String message, Map<String, Object> data) {
        GatewayResponse response = new GatewayResponse("success", message);
        response.setData(data);
        return response;
    }

    public static GatewayResponse error(String message) {
        return new GatewayResponse("error", message);
    }

    public static GatewayResponse error(String message, String errorCode) {
        GatewayResponse response = new GatewayResponse("error", message);
        response.setErrorCode(errorCode);
        return response;
    }

    public static GatewayResponse processing(String message) {
        return new GatewayResponse("processing", message);
    }

    public static GatewayResponse processing(String message, Map<String, Object> data) {
        GatewayResponse response = new GatewayResponse("processing", message);
        response.setData(data);
        return response;
    }

    // Добавление метаданных
    public GatewayResponse addMetadata(String key, Object value) {
        this.metadata.put(key, value);
        return this;
    }

    public GatewayResponse addData(String key, Object value) {
        this.data.put(key, value);
        return this;
    }

    // Вычисление времени обработки
    public void markComplete() {
        this.processingTimeMs = System.currentTimeMillis() - this.timestamp;
        this.metadata.put("processing_time_ms", this.processingTimeMs);
    }

    // Геттеры и сеттеры
    public String getRequestId() { return requestId; }
    public void setRequestId(String requestId) { this.requestId = requestId; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }

    public Map<String, Object> getData() { return data; }
    public void setData(Map<String, Object> data) { this.data = data; }

    public Map<String, Object> getMetadata() { return metadata; }
    public void setMetadata(Map<String, Object> metadata) { this.metadata = metadata; }

    public long getTimestamp() { return timestamp; }
    public void setTimestamp(long timestamp) { this.timestamp = timestamp; }

    public long getProcessingTimeMs() { return processingTimeMs; }
    public void setProcessingTimeMs(long processingTimeMs) { this.processingTimeMs = processingTimeMs; }

    public String getErrorCode() { return errorCode; }
    public void setErrorCode(String errorCode) { this.errorCode = errorCode; }

    public String getErrorDetails() { return errorDetails; }
    public void setErrorDetails(String errorDetails) { this.errorDetails = errorDetails; }
}
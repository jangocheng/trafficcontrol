package com.comcast.cdn.traffic_control.traffic_router.properties;

import org.apache.juli.logging.Log;

import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Properties;

public class PropertiesGenerator {
	private static Log log = org.apache.juli.logging.LogFactory.getLog(PropertiesGenerator.class);
	private final String propertiesFilePath;

	public PropertiesGenerator(final String propertiesFilePath) {
		this.propertiesFilePath = propertiesFilePath;
	}

	public String getProperty(String propertyName, String defaultValue) {
		final String value = loadFromPropertiesFile(propertyName);
		if (!value.isEmpty()) {
			return value;
		}

		return storeDefaultToPropertiesFile(propertyName, defaultValue);
	}

	protected String loadFromPropertiesFile(String propertyName) {
		Path path = Paths.get(propertiesFilePath);

		if (!Files.exists(path)) {
			return "";
		}

		try (InputStream inputStream = Files.newInputStream(path)) {
			final Properties properties = new Properties();
			properties.load(inputStream);

			String value = properties.getProperty(propertyName);

			if (value != null) {
				return value;
			}
		} catch (Exception e) {
			log.error("Failed reading property " + propertyName + " from file " + propertiesFilePath + " : " + e.getMessage());
		}

		return "";
	}

	protected String storeDefaultToPropertiesFile(String propertyName, String defaultValue) {
		Path path = Paths.get(propertiesFilePath);

		if (!Files.exists(path)) {
			try {
				path = Files.createFile(path);
			} catch (Exception e) {
				log.error("Failed attempting to create file " + propertiesFilePath + " to store property " + propertyName + " : " + e.getMessage());
				return "";
			}
		}

		try (OutputStream out = Files.newOutputStream(path)) {
			final Properties properties = new Properties();
			properties.setProperty(propertyName, defaultValue);
			properties.store(out, null);
			return defaultValue;
		} catch (Exception e) {
			log.error("Failed storing property " + propertyName + " to " + propertiesFilePath + " : " + e.getMessage());
		}

		return "";
	}
}

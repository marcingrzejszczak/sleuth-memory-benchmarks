package com.example;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

@SpringBootApplication
@RestController
public class SleuthApplication {

	public static void main(String[] args) {
		SpringApplication.run(SleuthApplication.class, args);
	}

	@Autowired RestTemplate restTemplate;
	@Value("${server.port}") int port;

	@GetMapping("/test")
	long test() {
		System.out.println("Calling myself");
		return this.restTemplate.getForObject("http://localhost:" + this.port + "/totalMemory", Long.class);
	}

	@GetMapping("/totalMemory")
	long totalMemory() {
		System.gc();
		return Runtime.getRuntime().totalMemory();
	}

	@Bean RestTemplate restTemplate() {
		return new RestTemplate();
	}
}

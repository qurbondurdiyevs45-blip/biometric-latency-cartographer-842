#include <GL/glew.h>
#include <vector>
#include <chrono>
#include <iostream>
#include <cmath>

class Renderer {
private:
    GLuint vertexShader;
    GLuint fragmentShader;
    GLuint shaderProgram;
    GLuint vbo;
    GLuint vao;

    const char* vertexShaderSource = R"glsl(
        #version 330 core
        layout (location = 0) in vec2 aPos;
        layout (location = 1) in vec3 aColor;
        out vec3 ourColor;
        void main() {
            gl_Position = vec4(aPos, 0.0, 1.0);
            ourColor = aColor;
        }
    )glsl";

    const char* fragmentShaderSource = R"glsl(
        #version 330 core
        out vec4 FragColor;
        in vec3 ourColor;
        void main() {
            FragColor = vec4(ourColor, 1.0f);
        }
    )glsl";

    void checkCompileErrors(GLuint shader, std::string type) {
        GLint success;
        GLchar infoLog[1024];
        if (type != "PROGRAM") {
            glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
            if (!success) {
                glGetShaderInfoLog(shader, 1024, NULL, infoLog);
                std::cerr << "ERROR::SHADER_COMPILATION_ERROR of type: " << type << "\n" << infoLog << std::endl;
            }
        } else {
            glGetProgramiv(shader, GL_LINK_STATUS, &success);
            if (!success) {
                glGetProgramInfoLog(shader, 1024, NULL, infoLog);
                std::cerr << "ERROR::PROGRAM_LINKING_ERROR of type: " << type << "\n" << infoLog << std::endl;
            }
        }
    }

public:
    Renderer() {
        glewExperimental = GL_TRUE;
        if (glewInit() != GLEW_OK) {
            throw std::runtime_error("Failed to initialize GLEW");
        }

        vertexShader = glCreateShader(GL_VERTEX_SHADER);
        glShaderSource(vertexShader, 1, &vertexShaderSource, NULL);
        glCompileShader(vertexShader);
        checkCompileErrors(vertexShader, "VERTEX");

        fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
        glShaderSource(fragmentShader, 1, &fragmentShaderSource, NULL);
        glCompileShader(fragmentShader);
        checkCompileErrors(fragmentShader, "FRAGMENT");

        shaderProgram = glCreateProgram();
        glAttachShader(shaderProgram, vertexShader);
        glAttachShader(shaderProgram, fragmentShader);
        glLinkProgram(shaderProgram);
        checkCompileErrors(shaderProgram, "PROGRAM");

        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);

        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
    }

    ~Renderer() {
        glDeleteVertexArrays(1, &vao);
        glDeleteBuffers(1, &vbo);
        glDeleteProgram(shaderProgram);
    }

    void renderFrame(float latencyMs) {
        // Map latency (0-50ms) to color (Green to Red)
        float intensity = std::min(latencyMs / 50.0f, 1.0f);
        float r = intensity;
        float g = 1.0f - intensity;
        float b = 0.2f;

        // Create a central indicator square
        float vertices[] = {
            -0.5f, -0.5f, r, g, b,
             0.5f, -0.5f, r, g, b,
             0.0f,  0.5f, r, g, b
        };

        glClearColor(0.05f, 0.05f, 0.05f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        glUseProgram(shaderProgram);
        glBindVertexArray(vao);

        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);

        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)(2 * sizeof(float)));
        glEnableVertexAttribArray(1);

        glDrawArrays(GL_TRIANGLES, 0, 3);
    }

    void setViewport(int width, int height) {
        glViewport(0, 0, width, height);
    }
};

extern "C" {
    Renderer* CreateRenderer() {
        return new Renderer();
    }

    void RenderDiagnostics(Renderer* renderer, float latency) {
        if (renderer) renderer->renderFrame(latency);
    }

    void DestroyRenderer(Renderer* renderer) {
        delete renderer;
    }
}
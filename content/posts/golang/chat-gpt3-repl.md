---
title: "Write a REPL using GPT-3 and Go"
description: ""
date: "2022-12-22T22:20:09+03:00"
thumbnail: "images/chat-gpt-repl.png"
categories:
- "Programming"
tags:
- "programming"
- "golang"
widgets:
- "categories"
- "taglist"
---

This blog post will discuss how to use the OpenAI Chat API in Golang. For this purpose we will create a simple REPL (Read-Eval-Print-Loop) that will use the GPT-3 API to generate the responses.

<!--more--> 

To use the OpenAI Chat API in Golang, you must obtain an API key from the OpenAI Developer Portal. Once you have an API key, you can use the following steps to make requests to the API:

Create a new Golang project and install openai library:
```shell
$ go mod init github.com/yourname/yourproject
$ go github.com/PullRequestInc/go-gpt3
```

The main function starts by reading in the OpenAI API key from the environment variable OPENAI_API_KEY. If the API key is not set, the program will exit with an error message. 
```go
	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		log.Fatal("Missing API KEY")
	}
```
To obtain an OpenAI API key, you will need to sign up for an account on the OpenAI website (https://beta.openai.com/signup/). Once you have created an account and verified your email address, you can access your API key by visiting the API section of the OpenAI dashboard (https://beta.openai.com/docs/api-overview/getting-started).

Next, the program creates a new client using the gpt3.NewClient function, passing in the API key as an argument.
```go
	client := gpt3.NewClient(apiKey)
```

The program then enters a loop where it reads in a prompt from the user via the command line and passes it to the GPT-3 engine using the CompletionWithEngine function. 
 
```go
	reader := bufio.NewScanner(os.Stdin)
	fmt.Print("Me> ")
	for reader.Scan() {
		resp, err := client.CompletionWithEngine(context.Background(),
			"text-davinci-002",
			gpt3.CompletionRequest{
				Prompt:    []string{reader.Text()},
				MaxTokens: gpt3.IntPtr(maxTokens),
			})
		if err != nil {
			log.Fatalln(err)
		}
		fmt.Println("GPT3>", resp.Choices[0].Text)
		fmt.Print("Me> ")
	}

```

The function returns a CompletionResponse object, which contains the generated text in the `Text` field. 

The generated text is then printed to the command line, and the loop continues until the user exits.

The full source code for this program is available on [GitHub](https://github.com/ubogdan/go-playground/tree/main/chat-gpt-repl).





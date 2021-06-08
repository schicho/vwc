# vwc

Beating C with 100 Lines of V.
A simple wc (word count) clone, designed to be faster than C.

This is my late addition to a trend form late 2019, about trying to write a simple wc clone in a few lines of code and trying to beat it's performance.

The [original article](https://chrispenner.ca/posts/wc), which started the trend, rewrote it in Haskell and my implementation is based on a program written in Go by [Ajeet D'Souza](https://ajeetdsouza.github.io/blog/posts/beating-c-with-70-lines-of-go/)

To be exact, as V's syntax is by desgin very close to Go, I mostly just rewrote Ajeet D'Souza's Go code in V.
The original source code can be found [here](https://github.com/ajeetdsouza/blog-wc-go).

## Benchmarking & comparison

I am going to compare the results using GNU time, as done by others in their articles. I am comparing the performance on parsing a 100 MB and 1 GB text file, with ascii characters only.

`$ /usr/bin/time -f "%es %MKB" wc test.txt`

For better comparison with the Go code, I will not rely on the stats given in the original article, but will compile the Go code myself using Go 1.16.

All benchmarks will be run on my system with the following specs:
- Intel Core i5-8265U @ 1.60 GHz @ 4 cores, 8 threads
- 8 GB DDR4 RAM @ 2667 MHz
- 1 TB M.2 SSD
- Ubuntu 20.04

The V and Go code use a 16 KB buffer for reading input.

## The two approaches

### Singlethreaded

The single threaded code reads into the buffer and then counts the words in that buffer, keeping track of wether we just started a new word previously or not. D'Souza's article goes into this in a lot more detail under the section 'Splitting the input'. The code can be directly transfered from Go to V with minor adjustments.
Only difference is, instead of relying on system calls to get the file size, I decided to count all the bytes manually in the process.

First we need two structs to organize our data in:

```V
struct FileChunk {
mut:
	prev_char_is_space bool
	buffer             []byte
}

struct Count {
mut:
	line_count u32
	word_count u32
}
```

These are quite self-explenatory. In a FileChunk we store 16KB of our file, and as the last char of the previous chunk might be a space and that would mean we start a new word with the new chunk.

The get_count() function is where the magic happens. Here we simply read every byte and compare it to the ascii values of different chars. Thus creating the logic of counting words and lines. V's `match` is here the perfect candidate, similar to the `switch()` of many other languages.

Note that here we need to declare all variables as mutable, and need to initialize them ourselfs, as required by V's design.

```V
fn get_count(chunk FileChunk) Count {
	mut count := Count{0, 0}
	mut prev_char_is_space := chunk.prev_char_is_space

	for b in chunk.buffer {
		match b {
			new_line {
				count.line_count++
				prev_char_is_space = true
			}
			space, tab, carriage_return, vertical_tab, form_feed {
				prev_char_is_space = true
			}
			else {
				if prev_char_is_space {
					prev_char_is_space = false
					count.word_count++
				}
			}
		}
	}

	return count
}
```

I declared all the chars as `const` in the file's beginning as they are also used in other functions.

```V
const (
	buffer_size     = 16 * 1024
	new_line        = `\n`
	space           = ` `
	tab             = `\t`
	carriage_return = `\r`
	vertical_tab    = `\v`
	form_feed       = `\f`
)
```

The only part that's still missing is the main function.
Here you can see that we read in the file into the buffer, counting the bytes read per read call, as in the last read we might have reached the end of the file before the buffer is full.

Error handling in V is similar to Go, but is done via the `or` block. This enforces proper error handling and leaves out the visual noise of checking for `err != nil`.

Now we just count the words in each chunk separately and the sum up the results to finally print them on the terminal.

```V
mut total_count := Count{0, 0}
mut byte_count := 0
mut last_char_is_space := true

mut buffer := []byte{len: buffer_size}

for {
    nbytes := file.read(mut buffer) or {
        match err {
            none { // EOF 'error', just break out of the loop.
                break
            }
            else {
                println(err)
            }
        }
        exit(1)
    }

    count := get_count(FileChunk{last_char_is_space, buffer[..nbytes]})
    last_char_is_space = is_space(buffer[nbytes - 1])

    total_count.line_count += count.line_count
    total_count.word_count += count.word_count
    byte_count += nbytes
}

println('$total_count.line_count $total_count.word_count $byte_count $file_path')
```

Now to the most exciting part! Comparing the results.

Note: I compiled the Go programs just with `go build main.go`. For the V programs I added the `-prod` flag to get optimized builds. Using `v -prod vwc_chunk.v`.
Without the production flag, the V compiler is blazingly fast, but the builds are less optimized and the time for parsing the file is actually closer to the one of GNU wc than to the one of GO.

| Program | File Size | Time      | Memory     |
| ---     | ---       | ---       | ---        |
| GNU wc  | 100 MB    |   0.60s   |  2268 KB   |
| GO wc   | 100 MB    |   0.29s   |  1588 KB   |
| V wc    | 100 MB    |   0.30s   |  1424 KB   |
| GNU wc  | 1 GB      |   6.52s   |  2264 KB   |
| GO wc   | 1 GB      |   3.26s   |  1596 KB   |
| V wc    | 1 GB      |   3.17s   |  1476 KB   |

So as we can see, both programs can easily beat C in performance and memory use. For the most part GO and V are very close to each other in performance.
The only difference is binary size, where V can beat GO by a lot. (Not that it really matters, but it's still interesting to see)

```
C  binary:  48 KB
V  binary: 108 KB
GO binary: 1.5 MB
```

### Multithreaded

As stated by D'Souza: "Admittedly, a parallel wc is overkill, but let’s see how far we can go".

In terms of code, V can again borrow many and almost all lines from the GO code.

The only difference using V was that the compiler not just errored, but often crashed using the concurrency features. I guess this is the result of V still being a quite new language and having a very small team of contributers, which are not hired by a company like GO with Google.
Also reference types work slightly differently in V than GO, which resulted in me being stuck with weird compiler errors and crashes. But this is probably also down to me being still new to the language and also me using V's concurrency features for the first time.

In the end I got it to work with a bit of trying and a bit of luck.

One thing needs to be said tho: V's concurrency features are not unstable. If it works, it works. But getting it to work in the first place was a bit tough.

```V
struct Count {
mut:
	line_count u32
	word_count u32
	byte_count int
}
```

For the multithreaded version, I included the number of bytes into each Count struct. This is needed as we now read from multiple threads.

```V
struct FileReader {
mut:
	file               os.File
	last_char_is_space bool
	mutex              sync.Mutex
}

fn (mut file_reader FileReader) read_chunk(mut buffer []byte) ?FileChunk {
	file_reader.mutex.@lock()
	defer {
		file_reader.mutex.unlock()
	}

	nbytes := file_reader.file.read(mut buffer) ? // Propagate error. Either EOF or read error.
	chunk := FileChunk{file_reader.last_char_is_space, buffer[..nbytes]}
	file_reader.last_char_is_space = is_space(buffer[nbytes - 1])
	return chunk
}
```

The FileReader struct is similar to the FileChunk, but that we now have a direct access to the file, and also include a mutex, so that multiple reading threads do not get ahead of each other and overwrite the `last_char_is_space` and we also have consistent results on HDDs, where parallel reads are not directly possible. You can see the mutex being locked and unlocked in the method `read_chunk`. Here is also another example of V's error handling, in which a possible error is just propagated to outer function using the `?`.

```V
fn file_reader_counter(mut file_reader FileReader, counts chan Count) {
	mut buffer := []byte{len: buffer_size}
	mut total_count := Count{0, 0, 0}

	for {
		chunk := file_reader.read_chunk(mut buffer) or {
			match err {
				none {
					// EOF 'error', just break out of the loop.
					break
				}
				else {
					println(err)
				}
			}
			exit(1)
		}

		count := get_count(chunk)

		total_count.line_count += count.line_count
		total_count.word_count += count.word_count
		total_count.byte_count += chunk.buffer.len
	}

	counts <- total_count
}
```

The `file_reader_counter` function is very similar to the main function before, only difference is that this function is now intended to be multithreaded using coroutines. You can see the channel in the funtion header, which is used to send the results. Basically each coroutine reads into it's buffer and after reading is finished, the next coroutine can read, while the other coroutine does it's counting of words.

In the main function the only task left to do is start as many coroutines as the CPU has logical cores an then collect the counts from the channel and combine the results.
We create one FileReader on the heap via the `&` and create a unbuffered channel of type Count.

Then via the `go` keyword we can start the coroutines just as in GO.

```V
mut file_reader := &FileReader{file, true, sync.new_mutex()}
counts := chan Count{}
num_workers := runtime.nr_cpus()

for i := 0; i < num_workers; i++ {
    go file_reader_counter(mut file_reader, counts)
}

mut total_count := Count{0, 0, 0}

for i := 0; i < num_workers; i++ {
    count := <-counts
    total_count.line_count += count.line_count
    total_count.word_count += count.word_count
    total_count.byte_count += count.byte_count
}
counts.close()

println('$total_count.line_count $total_count.word_count $total_count.byte_count $file_path')
```

Comparing the different implementations on the same files as before yields astonishing results:

| Program        | File Size | Time      | Memory     |
| ---            | ---       | ---       | ---        |
| GNU wc         | 100 MB    |   0.60s   |  2268 KB   |
| GO wc parallel | 100 MB    |   0.08s   |  1944 KB   |
| V wc parallel  | 100 MB    |   0.09s   |  2036 KB   |
| GNU wc         | 1 GB      |   6.52s   |  2264 KB   |
| GO wc parallel | 1 GB      |   0.71s   |  1976 KB   |
| V wc parallel  | 1 GB      |   0.88s   |  2032 KB   |

We can tell that GO is overall minimally faster than V and also consumes a bit less RAM. The main difference in RAM usage compared to D'Souza's article is probably that my laptop runs the programs on 8 threads, thus allocation more memory for reading the file, than the 4 threads in the GO article. Furthermore, I noticed that while GO's memory usage was very consiistent on each of the multiple runs I did, V's memory usage varied a bit more strongly on all attempts, almost reaching the same amount of memory usage like C.

## Conclusion

V itself is transpiled to C for optimized builds. You could almost say I compared C to C, but with on of the C being almost like GO.

Overall it was very interesting to see the comparison not only between C and V, but also GO and V. Using the same algorithms and functions obviously resulted in very similar results, but smaller differences could still be seen. Like in the other articles, this is not meant to be a V is better than C article. I wrote a very simplified version of the complete GNU wc. The only goal was to be faster, but still have the same results as GNU wc on pure ascii text.


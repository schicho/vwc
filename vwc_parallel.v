module main

import os
import sync
import runtime

// Adapted from:
// https://ajeetdsouza.github.io/blog/posts/beating-c-with-70-lines-of-go/
// https://github.com/ajeetdsouza/blog-wc-go

const (
	buffer_size     = 16 * 1024
	new_line        = `\n`
	space           = ` `
	tab             = `\t`
	carriage_return = `\r`
	vertical_tab    = `\v`
	form_feed       = `\f`
)

struct FileChunk {
mut:
	prev_char_is_space bool
	buffer             []byte
}

struct Count {
mut:
	line_count u32
	word_count u32
	byte_count int
}

fn get_count(chunk FileChunk) Count {
	mut count := Count{0, 0, 0}
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

fn is_space(b byte) bool {
	return b == new_line || b == space || b == tab || b == carriage_return || b == vertical_tab
		|| b == form_feed
}

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

fn main() {
	if os.args.len < 2 {
		println('no file path specified')
		exit(1)
	}

	file_path := os.args[1]
	mut file := os.open_file(file_path, 'rb') or {
		println('cannot open file')
		exit(1)
	}
	defer {
		file.close()
	}

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
}

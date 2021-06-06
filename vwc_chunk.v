module main

import os

// Adapted from:
// https://ajeetdsouza.github.io/blog/posts/beating-c-with-70-lines-of-go/
// https://github.com/ajeetdsouza/blog-wc-go

const (
	buffer_size     = 16 * 1024
	new_line        = '\n'[0]
	space           = ' '[0]
	tab             = '\t'[0]
	carriage_return = '\r'[0]
	vertical_tab    = '\v'[0]
	form_feed       = '\f'[0]
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
}

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

fn is_space(b byte) bool {
	return b == new_line || b == space || b == tab || b == carriage_return || b == vertical_tab
		|| b == form_feed
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

	mut total_count := Count{0, 0}
	mut byte_count := 0
	mut last_char_is_space := true

	mut buffer := []byte{len: buffer_size}

	for {
		nbytes := file.read(mut buffer) or {
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

		count := get_count(FileChunk{last_char_is_space, buffer[..nbytes]})
		last_char_is_space = is_space(buffer[nbytes - 1])

		total_count.line_count += count.line_count
		total_count.word_count += count.word_count
		byte_count += nbytes
	}

	println('$total_count.line_count $total_count.word_count $byte_count $file_path')
}

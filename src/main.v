module main

import cli { Command }
import os
import db.sqlite
import rand
import toml
// import encoding.iconv
import encoding.base64
import time
import einar_hjortdal.slugify
import arrays

const dbpath = os.home_dir() + '/repos/sniploc-bulma-carton/src/db/dbase.sqlite'

struct Snippet {
	uuid        string
	title       string = 'Placeholder for title'
	description string = 'Placeholder for description'
	content     string = 'Placeholder for content'
	stype       string
	parent      string
}

fn (s Snippet) to_toml() string {
	content := "[snippet]
id='${s.uuid}'

# Mandatory
title='${s.title}'

# Not mandatory
description='''
${s.description}
'''

# Not mandatory
content='''
${s.content}
'''

# Use `:SnpSyn` to see available syntax types
type='${s.stype}'

# Use `:SnpParent` to see available parent categories
[parent]
id='${s.parent}'"

	return content
}

fn main() {
	mut app := Command{
		name:        'default'
		description: 'Create code snippets right from within VIM!'
		version:     '0.0.1'
		execute:     fn (cmd Command) ! {
			println('This CLI app is meant to be used within VIM.')
			return
		}
		commands:    [
			Command{
				name:    'syn'
				execute: syn_func
			},
			Command{
				name:    'categories'
				execute: categories_func
			},
			Command{
				name:    'new'
				execute: new_func
			},
			Command{
				name:    'save'
				execute: save_func
				flags:   [
					cli.Flag{
						flag:        .string
						required:    true
						name:        'file'
						abbrev:      'f'
						description: 'Snippet template file path.'
					},
				]
			},
			Command{
				name:    'update'
				execute: update_func
				flags:   [
					cli.Flag{
						flag:        .string
						required:    true
						name:        'file'
						abbrev:      'f'
						description: 'Snippet template file path.'
					},
				]
			},
			Command{
				name:    'delete'
				execute: delete_func
				flags:   [
					cli.Flag{
						flag:        .string
						required:    true
						name:        'snippet'
						abbrev:      's'
						description: 'Snippet ID.'
					},
				]
			},
			Command{
				name:    'read'
				execute: read_func
				flags:   [
					cli.Flag{
						flag:        .string
						required:    true
						name:        'snippet'
						abbrev:      's'
						description: 'Snippet ID.'
					},
				]
			},
		]
	}
	app.setup()
	app.parse(os.args)
}

fn update_func(cmd Command) ! {
}

fn read_func(cmd Command) ! {
	snippet_id := cmd.flags.get_string('snippet') or {
		panic('Failed to get `snippet` flag: ${err}')
	}
	tmpfile := os.temp_dir() + '/snippet-' + snippet_id + '.toml'
	mut f := os.create(tmpfile) or { panic('Temp file ${tmpfile} not writable!') }

	db := sqlite.connect(dbpath)!
	query := 'SELECT uuid, title, description, content, type, parent_id FROM snpy_items WHERE uuid = ?'
	result := db.exec_param(query, snippet_id)!

	snp := Snippet{
		uuid:        result[0].vals[0]
		title:       result[0].vals[1]
		description: if result[0].vals[2] != '' {
			result[0].vals[2]
		} else {
			'Placeholder for description'
		}
		content:     if result[0].vals[3] != '' {
			result[0].vals[3]
		} else {
			'Placeholder for content'
		}
		stype:       result[0].vals[4]
		parent:      result[0].vals[5]
	}

	content := toml.encode(snp)

	f.write_string(content)!
	f.close()
	os.system('vim --remote-silent ${tmpfile}')
	print(tmpfile)
}

fn delete_func(cmd Command) ! {
	for {
		print('Are you sure you want to delete this snippet? [ y/n ]: ')
		line := os.get_line().trim_space()
		match line {
			'y' { break }
			'n' { return }
			else { continue }
		}
	}

	snippet_id := cmd.flags.get_string('snippet') or {
		panic('Failed to get `snippet` flag: ${err}')
	}
	db := sqlite.connect(dbpath)!
	query := 'DELETE FROM snpy_items WHERE uuid = ?'
	db.exec_param(query, snippet_id)!
}

fn syn_func(cmd Command) ! {
	db := sqlite.connect(dbpath)!
	query := 'SELECT name FROM snpy_type ORDER BY name'
	snippets := db.exec(query)!
	println('Create a new category')
	for row in snippets {
		println(row.vals[0])
	}
}

fn categories_func(cmd Command) ! {
	db := sqlite.connect(dbpath)!
	query := 'SELECT id, parents_title FROM parents_tree'
	categories := db.exec(query)!
	println('1\tSet as root item')
	for row in categories {
		// TODO: Is this interpolation correct?
		println('${row.vals[0]}\t${row.vals[1]}')
	}
}

fn new_func(cmd Command) ! {
	tmpfile := os.temp_dir() + '/snippet-' + rand.string(8)
	content := "[snippet]
# Mandatory
title='Placeholder for title'

# Not mandatory
description='''
Placeholder for description
'''

# Not mandatory
content='''
Placeholder for content
'''

# Use `:SnpSyn` to see available syntax types
type='Placeholder for type'

# Use `:SnpParent` to see available parent categories
[parent]
id='Placeholder for parent id'"

	mut f := os.create(tmpfile) or { panic('Temp file ${tmpfile} not writable!') }

	f.write_string(content)!
	f.close()
	println(tmpfile)
}

// Both creates new records and updates existing ones
// based on the snippet.id field's existece in the toml file.
fn save_func(cmd Command) ! {
	inputfile := cmd.flags.get_string('file') or { panic('Failed to get `file` flag: ${err}') }
	if !os.is_file(inputfile) {
		eprintln('Input file does not exist!')
		exit(1)
	}

	toml_text := os.read_file(inputfile)!
	doc := toml.parse_text(toml_text) or { panic(err) }

	title := doc.value('snippet.title').string().trim_space()
	slugifier := slugify.SlugifyOptions{
		to_lower:      true
		transliterate: false
	}
	slug := slugifier.make(title)
	// slug := iconv.vstring_to_encoding(title, 'ASCII')!.bytestr().to_lower().replace_each([
	// 	' ',
	// 	'-',
	// ])
	doc.value('snippet.description').str().trim_space
	mut description := doc.value('snippet.description').string().trim_space()
	mut content := doc.value('snippet.content').string().trim_space()
	parent_id := doc.value('parent.id').string().trim_space()
	mut snptype := doc.value('snippet.type').string().trim_space()

	if snptype == 'Placeholder for type' {
		eprintln('You didnot specify a correct syntax type!')
		exit(1)
	}

	if parent_id.int() == 0 {
		eprintln('You didnot specify a correct parent ID!')
		exit(1)
	}

	if content == 'Placeholder for content' {
		content = ''
	}

	if description == 'Placeholder for description' {
		description = ''
	}

	ts := time.now()
	creation_date := ts.format_ss()
	// uuid := base64.encode_str(creation_date.unix().str())
	uuid := base64.encode_str(ts.unix().str())

	if snptype == 'Create a new category' {
		snptype = 'inode/directory'
	}

	mut query := 'SELECT name FROM snpy_type ORDER BY name'

	db := sqlite.connect(dbpath)!

	results := db.exec(query)!
	snippets := arrays.map_indexed(results, fn (idx int, elem sqlite.Row) string {
		return elem.vals[0]
	})

	// TODO: val in array instead of .contains()
	if snptype != 'inode/directory' && !snippets.contains(snptype) {
		eprintln('You specified a non-existing syntax type!')
		exit(1)
	}

	sid := doc.value_opt('snippet.id') or { toml.Any('') }

	mut params := []string{cap: 9}
	params << title
	params << description
	params << parent_id
	params << slug
	params << snptype
	params << content
	params << creation_date
	params << uuid

	if sid.string() == '' {
		query = 'INSERT INTO snpy_items(title, description, parent_id, slug, type, content, creation_date, update_date, uuid )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
		params.insert(6, creation_date)
	} else {
		query = 'UPDATE snpy_items SET title = ?, description = ?, parent_id =
		?, slug = ?, type = ?, content = ?, update_date = ? WHERE uuid = ?'
		params[params.len - 1] = sid.string()
	}

	db.exec_param_many(query, params) or {
		eprintln('Couldnot save the snippet!')
		exit(1)
	}
	if db.get_affected_rows_count() == 1 {
		println('success')
	} else {
		eprintln('Error! Affected row count should be 1 but it is: ' +
			db.get_affected_rows_count().str())
		exit(1)
	}
}

package;

import haxe.io.BytesOutput;
import haxe.io.Path;
import format.tgz.Reader ;
import format.tar.Writer;
import sys.io.File;
import sys.FileSystem;
import tink.http.Fetch;
// Make the haxe manager in haxe
// This will cause no issues : )
class Main {
    public static function main() {
        var platform = "";
        switch (Sys.systemName()) {
            case "Windows": 
                platform = "windows";
            case "Mac": 
                platform = "mac";
            case "Linux": 
                platform = "linux64";
            case oops: 
                // who the hell uses BSD
                // cancelled
                Sys.println('Unknown OS ${oops}');
                Sys.exit(1);
        }
        var args = Sys.args();
        var cmd = args.shift();
        var root = Path.normalize(Path.join([Sys.programPath(), ".."]));
        if (!FileSystem.exists('$root/../releases'))
			FileSystem.createDirectory('$root/../releases');
		if (!FileSystem.exists('$root/../versions')) {
			FileSystem.createDirectory('$root/../versions');
        }
        switch (cmd) {
            case "download": 
                
                var target = null;
                var filename = null;
                var url = null;
                if (args[0] == null) {
                    Sys.println("Expected version");
                    Sys.exit(1);
                }
                switch (args[0]) {
                    case "latest": 
                        target = args[1];
                        if (target == null) {
                            target = "dev";
                        }
						url = 'https://build.haxe.org/builds/haxe/$platform/haxe_latest.tar.gz';
                        filename = "haxe_latest";
                    case "nightly":
                        target = args[2];
                        if (target == null) {
                            target = args[1];
                        }

						url = 'https://build.haxe.org/builds/haxe/$platform/haxe_${args[1]}.tar.gz';
                        filename = 'haxe_${args[1]}';
                    case file if (FileSystem.exists(file) && !FileSystem.isDirectory(file)): 
                        target = args[1];
                        var realpath = FileSystem.absolutePath(file);
                        var goodFile = File.read(realpath);
                        // TODO: Windows are actually zip files
                        // meaning this will always fail : (
						var outdir;
                        var zdata = null;
                        var tdata = null;
                        switch (platform) {
                            case "windows": 
                                zdata = haxe.zip.Reader.readZip(goodFile);
                                outdir = zdata.first().fileName;
                            default: 
                                tdata = new format.tgz.Reader(goodFile).read();
                                outdir = tdata.first().fileName;
                        }
                        goodFile.close();
                        if (target == null) {
                            Sys.println("Cannot install from local file without providing version");
                            Sys.exit(1);
                        }
                        var oldCwd = Sys.getCwd();
                        Sys.setCwd(Path.normalize('$root/../releases'));
                        switch (platform) {
                            case "windows": 
                                for (entry in zdata) {
                                    haxe.zip.Tools.uncompress(entry);
                                    if (entry.data == null || entry.fileSize == 0) {
                                        FileSystem.createDirectory(entry.fileName);
                                    } else {
										File.saveBytes(entry.fileName, entry.data);
                                    }
                                    
                                }
                            default: 
							    extractTar(tdata);
                        }
                        

                        Sys.setCwd(oldCwd);
                        if (FileSystem.exists(Path.join([root, '../versions/$target'])))
						    FileSystem.deleteFile(Path.join([root, '../versions/$target']));
						

                        link(Path.join([root, "../versions/", target]), Path.join([root, "../releases/", outdir]));

                        Sys.exit(0);
                    case _: 
                        target = args[1];
                        if (target == null) {
                            target = args[0];
                        }
                        var thingie = args[0];
						url = 'https://github.com/HaxeFoundation/haxe/releases/download/$thingie/haxe-$thingie-$platform.tar.gz';
                        filename = 'haxe-$thingie-$platform';
                        
                        
                        


                }
                var oldCwd = Sys.getCwd();
                Sys.setCwd(Path.join([root, "../releases"]));
                safeDelete('$filename.tar.gz');
                tink.http.Client.fetch(url).all().handle((cb) -> {
                    switch (cb) {
                        case Success(data):
                            File.saveBytes('$filename.tar.gz', data.body);
							var goodFile = File.read(filename + ".tar.gz");
							var data = new Reader(goodFile).read();
							var outdir = data.first().fileName;
                            goodFile.close();
                            extractTar(data);
                            safeDelete(filename + ".tar.gz");
                            Sys.setCwd(oldCwd);
                            safeDelete('$root/../versions/$target');
                            link(Path.join([root, "../versions/", target]), Path.join([root, "../releases/", outdir]));
                            Sys.println("Successfully added version " + target);
                            Sys.exit(0);
                        case Failure(failure):
                            Sys.println("Failed to connect : (");
                            Sys.exit(1);
                    }
                });
            case "select": 
                if (args[0] != null) {
                    if (FileSystem.exists('$root/../versions/${args[0]}')) {
                        safeDelete('$root/haxe');
                        safeDelete('$root/haxelib');
                        safeDelete('$root/../std');
                        link('$root/haxe', '$root/../versions/${args[0]}/haxe',true);  
                        link('$root/haxelib', '$root/../versions/${args[0]}/haxelib',true);   
                        link('$root/../std', '$root/../versions/${args[0]}/std');   
                    } else if (FileSystem.exists('$root/../releases/${args[0]}')) {
						safeDelete('$root/../bin/haxe');
						safeDelete('$root/../bin/haxelib');
						safeDelete('$root/../std');
						link('$root/../bin/haxe', '$root/../releases/${args[0]}/haxe', true);
						link('$root/../bin/haxelib', '$root/../releases/${args[0]}/haxelib', true);
                        if (platform != "windows") {
							Sys.command("chmod +x", ['$root/../bin/haxe']);
							Sys.command("chmod +x", ['$root/../bin/haxelib']);
                        }
						link('$root/../std', '$root/../releases/${args[0]}/std');   
                    } else {
                        Sys.println("Not a valid release or version");
                        Sys.exit(1);
                    }
                } else {
                    Sys.println("Version required : (");
                    Sys.exit(1);
                }
            case "list" | "ls": 
                for (file in FileSystem.readDirectory('$root/../versions')) {
                    Sys.println(file);
                }
        }
    }
    /**
     * Extract tars into CWD (set cwd before entering this)
     * @param data 
     */
    static function extractTar(data:format.tar.Data) {
        for (file in data) {
            if (file.data == null || file.data.length == 0) {
                // Directory
                FileSystem.createDirectory(file.fileName);
            } else {
                File.saveBytes(file.fileName, file.data);
            }
        }
    }
    static function safeDelete(file:String) {
        if (FileSystem.exists(file))
            FileSystem.deleteFile(file);
    }
    static function link(to:String, from:String, file:Bool = false) {
        switch (Sys.systemName()) {
            case "Windows": 
                if (file) {
                    Sys.command("mklink", [
                        to,
                        from
                    ]);
                }   
                else  {
                    Sys.command("mklink", [
                        "/d",
                        to,
                        from,
                    ]);
                }
                    
            default: 
                Sys.command("ln", [
                    "-s",
                    from,
                    to
                ]);
        }
    }
}
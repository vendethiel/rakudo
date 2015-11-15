class CompUnit::Repository::FileSystem does CompUnit::Repository::Locally does CompUnit::Repository {
    has %!loaded;
    has $!precomp;

    my %extensions =
      Perl6 => <pm6 pm>,
      Perl5 => <pm5 pm>,
      NQP   => <nqp>,
      JVM   => ();

    # global cache of files seen
    my %seen;

    method need(
        CompUnit::DependencySpecification $spec,
        CompUnit::PrecompilationRepository $precomp = self.precomp-repository(),
        :$line
    )
        returns CompUnit:D
    {
        state Str $precomp-ext = $*VM.precomp-ext;  # should be $?VM probably
        my $name               = $spec.short-name;
        my $id = nqp::sha1($name ~ $*REPO.id);
        my $handle = $precomp.may-precomp ?? $precomp.load($id) !! CompUnit::Handle;
        my $base := $!prefix.child($name.subst(:g, "::", $*SPEC.dir-sep) ~ '.').Str;
        my $compunit;

        return %!loaded{$name} if %!loaded{$name}:exists;

        if $handle {
            return %!loaded{$name} = %seen{$base} = CompUnit.new(
                $base, :name($name), :extension(''), :has-precomp, :$handle, :repo(self)
            );
        }
        else {
            # pick a META6.json if it is there
            if (my $meta = $!prefix.child('META6.json')) && $meta.f {
                my $json = from-json $meta.slurp;
                if $json<provides>{$name} -> $file {
                    my $path = $file.IO.is-absolute ?? $file !! $!prefix.child($file);

                    $compunit = %seen{$path} = CompUnit.new(
                        $path, :name($name), :extension(''), :has-source, :repo(self)
                    ) if IO::Path.new-from-absolute-path($path).f;
                }
            }
            # deduce path to compilation unit from package name
            else {
                if %seen{$base} -> $found {
                    $compunit = $found;
                }

                # have extensions to check
                elsif %extensions<Perl6> -> @extensions {
                    for @extensions -> $extension {
                        my $path = $base ~ $extension;

                        $compunit = %seen{$base} = CompUnit.new(
                          $path, :$name, :$extension, :has-source, :repo(self)
                        ) if IO::Path.new-from-absolute-path($path).f;
                    }
                }
            }
        }

        if $compunit {
            if $precomp.may-precomp and $precomp.precompile($compunit, $id) {
                $handle = $precomp.load($id);
                return %!loaded{$name} = %seen{$base} = CompUnit.new(
                    $base, :name($name), :extension(''), :has-precomp, :$handle, :repo(self)
                );
            }
            else {
                $compunit.load(:$line);
                return %!loaded{$compunit.name} = $compunit;
            }
        }

        return self.next-repo.need($spec, $precomp, :$line) if self.next-repo;
        nqp::die("Could not find $spec in:\n" ~ $*REPO.repo-chain.map(*.Str).join("\n").indent(4));
    }

    method load(Str:D $file, :$line) returns CompUnit:D {
        state Str $precomp-ext = $*VM.precomp-ext;  # should be $?VM probably

        # We have a $file when we hit: require "PATH" or use/require Foo:file<PATH>;
        my $has_precomp = $file.ends-with($precomp-ext);
        my $path = $file.IO.is-absolute
                ?? $file
                !! $!prefix.child($file);

        if IO::Path.new-from-absolute-path($path).f {
            my $compunit = %seen{$path} = CompUnit.new(
              $path, :$file, :extension(''), :has-source(!$has_precomp), :$has_precomp, :repo(self)
            );
            $compunit.load(:$line);
            return %!loaded{$compunit.name} = $compunit;
        }

        return self.next-repo.load($file, :$line) if self.next-repo;
        nqp::die("Could not find $file in:\n" ~ $*REPO.repo-chain.map(*.Str).join("\n").indent(4));
    }

    method short-id() { 'file' }

    method loaded() returns Iterable {
        return %!loaded.values;
    }

    method files($file, :$name, :$auth, :$ver) {
        my $base := $file.IO;
        $base.f
         ?? { files => { $file => $base.path }, ver => Version.new('0') }
         !! ();
    }

    method precomp-repository() returns CompUnit::PrecompilationRepository {
        $!precomp := CompUnit::PrecompilationRepository::Default.new(
            :store(
                CompUnit::PrecompilationStore::File.new(
                    :prefix(self.prefix.child('.precomp')),
                )
            ),
        ) unless $!precomp;
        $!precomp
    }
}

# vim: ft=perl6 expandtab sw=4

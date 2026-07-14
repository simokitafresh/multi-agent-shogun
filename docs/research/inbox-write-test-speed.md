# inbox write test speed

## Improvement candidates

1. [[test_inbox_write.bats]] cloned the complete git template for every git-oriented test with an ordinary `cp -a`; implemented `--reflink=auto` to preserve isolation through CoW where supported.
2. Review-context tests repeatedly execute semantic and memory context generation through [[inbox_write.sh]]; profile a bounded shared context fixture next.
3. Report-received tests repeatedly execute report-format and git-overlap checks; cache only immutable inputs if these become dominant.

The change does not mock or skip [[inbox_write.sh]]. Every test still receives a private writable git repository, and `--reflink=auto` falls back to the original byte copy on filesystems without clone support.

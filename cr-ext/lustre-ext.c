/* lustre.c - Lustre crash extensions
 *
 * Copyright (C) 2007, Lawrence Livermore National Labs
 * Auther: Brian Behlendorf
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include "defs.h"

#define UINT32_LEN   10 /* ceil(log10(UINT_MAX)) */
#define UINT64_LEN   20 /* ceil(log10(ULONG_MAX)) */

/* three types of trace_data in linux */
enum {
        TCD_TYPE_PROC = 0,
        TCD_TYPE_SOFTIRQ,
        TCD_TYPE_IRQ,
        TCD_TYPE_MAX
};

#define LUSTRE_PAGES		1
#define LUSTRE_DAEMON_PAGES	2
#define LUSTRE_STOCK_PAGES	3

static char const lustre_1_pfx[] = "";
static char const lustre_2_pfx[] = "cfs_";

#define FMT_PAGE_COUNT		"$%*d = %d"

static char const fmt_page_list_head[] =
        "$%*d = (struct list_head *) 0x%lx";

static char const fmt_trace_page_fmt[] =
        "%%lx\n"
        "struct %strace_page {\n"
        "  page = 0x%%lx,\n"
        "  linkage = {\n"
        "    next = 0x%%lx,\n"
        "    prev = 0x%%lx\n"
        "  },\n"
        "  used = %%d,\n"
        "  cpu = %%d,\n"
        "  type = %%d\n"
        "}\n";

static char const   lustre2_pfx[] = "cfs_";
static char const * name_prefix   = lustre2_pfx;
static char const * fmt_trace_page;

void cmd_lustre();
char *help_lustre[];

static struct command_table_entry command_table[] = {
        { "lustre", cmd_lustre, help_lustre, 0 },
        { NULL }
};


void _init(void)
{
        register_extension(command_table);
}

void _fini(void) { }


/* Given a pointer to a page frame append the assoicated linear
 * address range to the passed file descriptor.
 */
static int
lustre_write_page_frame(int fd, ulong tp_addr, ulong kvaddr, int used) {
        char buf[PAGESIZE()];
        physaddr_t kpaddr;
        int retry = 0;
        ssize_t rc, count = 0;

        if (!is_page_ptr(kvaddr, &kpaddr)) {
                error(WARNING, "Skipping trace page 0x%lx which references "
                      "an invalid page pointer (0x%x)\n", tp_addr, kvaddr);
                return -EADDRNOTAVAIL;
        }

        if (!readmem(kpaddr, PHYSADDR, buf, used,
                     "trace page data", RETURN_ON_ERROR)) {
                error(WARNING, "Skipping trace page 0x%lx, unable to read "
                      "data from physical address (0x%x)\n", tp_addr, kpaddr);
                return -EIO;
        }

        while (count < used) {
                rc = write(fd, buf + count, used - count);
                if (rc >= 0) {
                        count += rc;

                        if ((rc == 0) && (retry++ > 5)) {
                                error(WARNING, "Partial trace page 0x%lx "
                                      "written to output file (%d/%d bytes)\n",
                                      tp_addr, count, used);
                                return count;
                        }
                } else {
                        error(WARNING, "Unable to write to output file: "
                              "%s (%d)\n", strerror(errno), errno);
                        return -rc;
                }
        }

        return count;
}


/* Walk the list of trace_pages linked off the passed list_head pointer */
static int
lustre_walk_trace_pages(int cpu, int fd, ulong lh_addr)
{
        static char const name_txt[] = "cfs_trace_page";
        char const * name = name_txt + ((*name_prefix == '\0')
                                        ? (sizeof(lustre2_pfx) - 1) : 0);

        struct list_data ld;
        ulong tp_addr, tp_page, tp_next, tp_prev;
        int tp_used, tp_cpu, tp_type, count, rc, i = 0, ret = 0;

        printf("lustre_walk_trace_pages(%d, %d, 0x%lx)\n", cpu, fd, lh_addr);

        BZERO(&ld, sizeof(struct list_data));
        ld.start = lh_addr;
        ld.list_head_offset = MEMBER_OFFSET((char *)name, "linkage");
        ld.structname_args = 1;
        ld.structname = (char **)GETBUF(sizeof(char *) * ld.structname_args);
        ld.structname[0] = (char *)name;
        ld.flags = TRUE;

        open_tmpfile();

        hq_open();
        count = do_list(&ld);
        hq_close();

        rewind(pc->tmpfile);
        while (i < (count - 1)) {
                i++;

                if ((rc = fscanf(pc->tmpfile, fmt_trace_page, &tp_addr,
                                 &tp_page, &tp_next, &tp_prev, &tp_used,
                                 &tp_cpu, &tp_type)) != 7) {
                        close_tmpfile();
                        error(WARNING, "Skipping %d remaining trace pages "
                              "on CPU %d due to parse error, rc = %d\n", 
                              count - i, cpu, rc);
                        return ret;
                }

                /* Ensure this page belongs to the CPU list being walked */
#if 0
                if (tp_cpu != cpu) {
                        error(WARNING, "Skipping trace page 0x%lx which is "
                              "owned by CPU %d not CPU %d\n",
                              tp_addr, tp_cpu, cpu);
                        continue;
                }
#endif

                /* Validate the list heads for some sanity */
                if ((tp_next == 0) || (tp_prev == 0)) {
                        error(WARNING, "Trace page 0x%lx has bogus next "
                              "(0x%lx) or prev (0x%lx) pointers\n",
                              tp_addr, tp_next, tp_prev);
                        continue;
                }

                if ((tp_used < 0) || (tp_used > PAGESIZE())) {
                        error(WARNING, "Trace page 0x%lx has bogus used "
                              "size (%d)\n", tp_used);
                        continue;
                }
#if 0
                printf("i = %d, count = %d, tp_addr = 0x%lx, tp_page = 0x%lx, "
                       "tp_next = 0x%lx, tp_prev = 0x%lx, tp_used = 0x%lx "
                       "tcpu = %d\n", i, count, tp_addr, tp_page, tp_next,
                       tp_prev, tp_used, tp_cpu);
#endif
                rc = lustre_write_page_frame(fd, tp_addr, tp_page, tp_used);
                if (rc >= 0)
                        ret += 1;
        }

        close_tmpfile();
        return ret;
}


/* Aquire the debug page list head pointer for this CPU and walk them */
static int
lustre_walk_cpus(int type, int cpu, int fd, int mode)
{
        static char const cmd_fmt_fmt[] =
                "p (*%strace_data[%%i])[%%i].tcd.tcd_%%s";
        char cmd_fmt[sizeof(cmd_fmt_fmt) + sizeof(lustre2_pfx)];

        char cmd_count[sizeof(cmd_fmt) + (2 * UINT32_LEN) + 20];
        char cmd_head[sizeof(cmd_count)];
        int rc, count = 0;
        ulong lh_addr;

        sprintf(cmd_fmt, cmd_fmt_fmt, name_prefix);
        printf("lustre_walk_cpus(%d, %d, %d)\n", cpu, fd, mode);

        switch (mode) {
        case LUSTRE_PAGES:
                sprintf(cmd_count, cmd_fmt, type, cpu, "cur_pages");
                sprintf(cmd_head,  cmd_fmt, type, cpu, "pages.next");
                break;
        case LUSTRE_DAEMON_PAGES:
                sprintf(cmd_count, cmd_fmt, type, cpu, "cur_daemon_pages");
                sprintf(cmd_head,  cmd_fmt, type, cpu, "daemon_pages.next");
                break;
        case LUSTRE_STOCK_PAGES:
                sprintf(cmd_count, cmd_fmt, type, cpu, "cur_stock_pages");
                sprintf(cmd_head,  cmd_fmt, type, cpu, "stock_pages.next");
                break;
        default:
                return -EINVAL;
        }
        printf("cmd:\t%s\n\t%s\n", cmd_count, cmd_head);

        /* Aquire the expected number of debug pages */
        open_tmpfile();
        if (!gdb_pass_through(cmd_count, pc->tmpfile, GNU_RETURN_ON_ERROR)) {
                close_tmpfile();
                error(FATAL, "gdb request failed: \"%s\"\n", cmd_count);
                return -EINVAL;
        }

        rewind(pc->tmpfile);
        if ((rc = fscanf(pc->tmpfile, FMT_PAGE_COUNT, &count)) != 1) {
                close_tmpfile();
                error(FATAL, "gdb unexpected result: \"%s\", rc = %d\n",
                      cmd_count, rc);
                return -EINVAL;
        }
        close_tmpfile();

        /* Skip CPUs with no debug pages */
        if (count == 0)
                return count;

        /* Aquire the list head address for the tage list */
        open_tmpfile();
        if (!gdb_pass_through(cmd_head, pc->tmpfile, GNU_RETURN_ON_ERROR)) {
                close_tmpfile();
                error(FATAL, "gdb request failed: \"%s\"\n", cmd_head);
                return -EINVAL;
        }

        rewind(pc->tmpfile);
        if ((rc = fscanf(pc->tmpfile, fmt_page_list_head, &lh_addr)) != 1) {
                close_tmpfile();
                error(FATAL, "gdb unexpected result: \"%s\", rc = %d\n",
                      cmd_head, rc);
                return -EINVAL;
        }
        close_tmpfile();

        return lustre_walk_trace_pages(cpu, fd, lh_addr);
}


void
cmd_lustre_log(char *name)
{
        static char const sym[] = "cfs_trace_data";

        struct syment *sp;
        int i, rc, count, total = 0, fd;
        int type;

        fd = open(name, O_CREAT | O_EXCL | O_APPEND | O_WRONLY,
                  S_IRUSR | S_IWUSR);
        if (fd == -1) {
                error(FATAL, "Unable to open log file \"%s\": %s (%d)\n",
                      name, strerror(errno), errno);
                return;
        }

        do {
                sp = symbol_search((char *)sym);
                if (sp != NULL) break;
                sp = symbol_search((char *)sym + sizeof(lustre2_pfx) - 1);
                name_prefix = "";
                if (sp != NULL) {
                        error(WARNING, "this is lustre 1.x series\n");
                        break;
                }

                error(FATAL, "cannot resolve \"%s\"\n"
                      "Ensure the libcfs module symbols are loaded "
                      "with \"mod -S\"\n", sym);
                return;
        } while (0);

        {
                char * p = malloc(sizeof(fmt_trace_page_fmt)
                                  + sizeof(lustre2_pfx) - 1);
                sprintf(p, fmt_trace_page_fmt, name_prefix);
                fmt_trace_page = p;
        }

        for (type = 0; type < TCD_TYPE_MAX; type++) {
                for (i = 0; i < kt->cpus; i++) {
                        count = 0;

                        rc = lustre_walk_cpus(type, i, fd, LUSTRE_PAGES);
                        if (rc >= 0)
                                count += rc;

                        rc = lustre_walk_cpus(type, i, fd,
                                              LUSTRE_DAEMON_PAGES);
                        if (rc >= 0)
                                count += rc;
                        error(INFO, "Dumped %d debug pages from type %d -"
                              " CPU %d\n", count, type, i);
                        total += count;
                }
        }

        if (fsync(fd) == -1)
                error(WARNING, "Unable to sync log file \"%s\" it may be "
                      "incomplete: %s (%d)\n", name, strerror(errno), errno);

        if (close(fd) == -1)
                error(WARNING, "Unable to close log file \"%s\": "
                      "%s %d\n", name, strerror(errno), errno);

        error(INFO, "Dumped %d total debug pages from %d CPUs to %s\n",
              total, kt->cpus, name);
}


void
cmd_lustre(void)
{
        int c;

        while ((c = getopt(argcnt, args, "l:")) != EOF) {
                switch (c) {
                case 'l':
                        if (strlen(optarg) == 0)
                                argerrs++;
                        else
                                cmd_lustre_log(optarg);

                        break;
                default:
                        argerrs++;
                        break;
                }
        }

        if (argerrs)
                cmd_usage(pc->curcmd, SYNOPSIS);

        fprintf(fp, "\n");
}

char *help_lustre[] = {
        "lustre",                              /* command name */
        "lustre specific debug commands",      /* short description */
        "[-l <file>]",                         /* argument synopsis */
        "  This command displays lustre specific data.\n",
        "       -l  Extract lustre kernel debug data to <file>",
        "           (use 'lctl df <file>' for ascii text)",
        "\nEXAMPLE",
        "    crash> lustre -l /tmp/lustre.log",
        NULL
};
/*
 * Local Variables:
 * mode: C
 * c-file-style: "stroustrup"
 * indent-tabs-mode: nil
 * c-basic-offset: 8
 * End:
 *
 * end of lustre-ext.c */

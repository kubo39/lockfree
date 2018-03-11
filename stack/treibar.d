import core.atomic;

shared class Stack(T)
{
    bool empty() const @property
    {
        return this.head.atomicLoad!(MemoryOrder.acq) is null;
    }

    void push(T value)
    {
        auto newHead = new shared Node(value, null);
        shared Node* oldHead;
        do {
            oldHead = head.atomicLoad!(MemoryOrder.raw);
            newHead.next = oldHead;
        } while (!cas(&this.head, oldHead, newHead));
    }

    shared(T)* pop() @property
    {
        shared Node* oldHead, newHead;
        do {
            oldHead = head.atomicLoad!(MemoryOrder.acq);
            if (oldHead is null)
                return null;
            newHead = oldHead.next;
        } while (!cas(&this.head, oldHead, newHead));
        return &oldHead.value;
    }

private:

    struct Node
    {
        T value;
        Node* next;
    }

    Node* head;
}


unittest
{
    /// smoke test.
    {
        auto s = new shared Stack!int;
        s.push(1);
        assert(*s.pop == 1);
        assert(s.pop is null);
    }

    /// push and pop.
    {
        auto s = new shared Stack!int;
        s.push(1);
        s.push(2);
        s.push(3);
        assert(*s.pop == 3);
        s.push(4);
        assert(*s.pop == 4);
        assert(*s.pop == 2);
        assert(*s.pop == 1);
        assert(s.pop is null);
        s.push(5);
        assert(*s.pop == 5);
        assert(s.pop is null);
    }

    /// stress.
    {
        import core.thread : Thread, thread_joinAll;
        import std.random : uniform;

        const THREADS = 4;
        auto s = new shared Stack!int;
        shared(ulong) len = 0;

        foreach (t; 0 .. THREADS)
        {
            new Thread({
                    foreach (i; 0 .. 1000)
                    {
                        if (uniform(0, t+1) == 0)
                        {
                            auto x = s.pop;
                            if (x !is null)
                                len.atomicOp!"-="(1);
                        }
                        else
                        {
                            s.push(t + THREADS * i);
                            len.atomicOp!"+="(1);
                        }
                    }
                });
        }

        thread_joinAll;

        auto last = [ulong.max, ulong.max, ulong.max, ulong.max];
        while (!s.empty)
        {
            auto x = s.pop;
            auto t = *x % THREADS;
            assert(last[t] > *x);
            last[t] = *x;
            len.atomicOp!"-="(1);
        }
        assert(len.atomicLoad!(MemoryOrder.seq) == 0);
    }
}

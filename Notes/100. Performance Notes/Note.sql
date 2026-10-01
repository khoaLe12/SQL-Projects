



-- IMPORTANT NOTES
-- 1. This is a very rich set of performance notes (kind of advanced knowledge, deep dive into many important aspects of performance) -> read it carefully and search more on SQL document for better understand before applying it to your project
-- 2. The notes are categorized into many 




-- UNDERSTAND THE ARCHITECTURE OF PROCESSOR, PROCESS, TASK, THREAD
-- 1. Processor
--	+ The hardware execution unit inside CPU (a core or logical processor).
--	+ It provides the actual computational resources (ALUs, registers, caches).
--	+ At any instant, a processor runs one thread (or two if hyper-threading is enabled).
-- 2. Process
--	+ A running application (like SQL Server, Chrome, or Word).
--		- Each SQL instance is a process named sqlservr.exe.
--		- SQL Server Agent has a seperate process SQLAgent.exe.
--		- SQL Full-Text Filter Daemon Launcher process is fdlauncher.exe. 
--	+ Each process has its own memory space and resources.
--	+ A process can contain many tasks and threads.
-- 3. Task
--	+ A unit of work that needs to be done (e.g, executing a query, rendering a webpage, performing a calculation).
--	+ Tasks are higher-level abstractions - essentially the "job description" or "a collection of instructions".
--	+ Each task is assigned to a thread for execution.
-- 4. Thread
--	+ The execution vehicle for a task.
--	+ A thread carries the context (registers, program counter, stack pointer) for its task.
--	+ Threads are scheduled by the OS onto processors.
--	+ A process can spawn many threads to handle multiple tasks concurrently.
-- 5. How they work together
--	+ Process: the application (SQL Server).
--	+ Task: a unit of work inside the process (query execution).
--	+ Thread: the worker assigned to run that task.
--	+ Processor: the hardware that executes the thread's instructions.
-- 6. Multitasking
--	+ The ability of an operating system to handle multiple processes (applications) at the same time.
--	+ The OS rapidly switches the CPU between processes, giving the illusion that they're running simultaneously.
-- 7. Multithreading
--	+ The ability of a single process (application) to split its work into multiple threads.
--	+ Threads share the same memory space if the process but run independently. This allows finer-grained concurrency within one application.
-- 8. Parallelism
--	+ True simultaneous execution of multiple threads or task across multiple processors (cores).
--	+ If a task can be divided into independent subtasks, those subtasks can be run at the same time on different cores.
--	+ Ex: SQL Server splits a query into multiple subtasks (scanning different parts of a table know as partitions) and runs them in parallel across several cores.
/*
 * MPI Ring Communication Test
 * 
 * This program tests MPI communication across multiple nodes by passing
 * a token around a ring. Each process receives from its left neighbor
 * and sends to its right neighbor.
 *
 * Compile: mpicc -o mpi_ring_test mpi_ring_test.c
 * Run: mpirun -np 4 ./mpi_ring_test
 */

#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#define TOKEN_VALUE 42
#define MAX_HOSTNAME 256

int main(int argc, char** argv) {
    int world_size, world_rank;
    int token;
    char hostname[MAX_HOSTNAME];
    char processor_name[MPI_MAX_PROCESSOR_NAME];
    int name_len;
    
    // Initialize MPI
    MPI_Init(&argc, &argv);
    
    // Get process information
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    MPI_Get_processor_name(processor_name, &name_len);
    gethostname(hostname, MAX_HOSTNAME);
    
    // Print initial information
    printf("Rank %d/%d on host %s (MPI processor: %s) - PID: %d\n", 
           world_rank, world_size, hostname, processor_name, getpid());
    fflush(stdout);
    
    // Synchronize all processes
    MPI_Barrier(MPI_COMM_WORLD);
    
    if (world_rank == 0) {
        printf("\n=== Starting MPI Ring Test with %d processes ===\n\n", world_size);
        fflush(stdout);
    }
    
    // Ring communication test
    if (world_rank == 0) {
        // Rank 0 starts the ring by sending to rank 1
        token = TOKEN_VALUE;
        printf("[Rank 0] Sending token %d to rank 1\n", token);
        fflush(stdout);
        
        MPI_Send(&token, 1, MPI_INT, 1, 0, MPI_COMM_WORLD);
        
        // Rank 0 receives from the last rank (closing the ring)
        MPI_Recv(&token, 1, MPI_INT, world_size - 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("[Rank 0] Received token %d from rank %d - RING COMPLETE!\n", 
               token, world_size - 1);
        fflush(stdout);
        
        // Verify token value
        if (token == TOKEN_VALUE + world_size - 1) {
            printf("\n✓ SUCCESS: Token passed through all %d processes correctly!\n", world_size);
        } else {
            printf("\n✗ ERROR: Token value incorrect! Expected %d, got %d\n", 
                   TOKEN_VALUE + world_size - 1, token);
        }
    } else {
        // All other ranks receive from rank-1 and send to rank+1
        MPI_Recv(&token, 1, MPI_INT, world_rank - 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("[Rank %d] Received token %d from rank %d\n", 
               world_rank, token, world_rank - 1);
        fflush(stdout);
        
        // Increment the token
        token++;
        
        // Send to next rank (wraps around to 0 for the last rank)
        int next_rank = (world_rank + 1) % world_size;
        printf("[Rank %d] Sending token %d to rank %d\n", 
               world_rank, token, next_rank);
        fflush(stdout);
        
        MPI_Send(&token, 1, MPI_INT, next_rank, 0, MPI_COMM_WORLD);
    }
    
    // Synchronize before collective operations
    MPI_Barrier(MPI_COMM_WORLD);
    
    // Test collective operations
    if (world_rank == 0) {
        printf("\n=== Testing MPI Collective Operations ===\n\n");
        fflush(stdout);
    }
    
    // Broadcast test
    int broadcast_data = 0;
    if (world_rank == 0) {
        broadcast_data = 12345;
        printf("[Rank 0] Broadcasting value: %d\n", broadcast_data);
        fflush(stdout);
    }
    
    MPI_Bcast(&broadcast_data, 1, MPI_INT, 0, MPI_COMM_WORLD);
    printf("[Rank %d] Received broadcast value: %d\n", world_rank, broadcast_data);
    fflush(stdout);
    
    MPI_Barrier(MPI_COMM_WORLD);
    
    // Reduction test
    int local_value = world_rank + 1;
    int sum = 0;
    
    MPI_Reduce(&local_value, &sum, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);
    
    if (world_rank == 0) {
        int expected_sum = (world_size * (world_size + 1)) / 2;
        printf("\n[Rank 0] Sum reduction result: %d (expected: %d)\n", sum, expected_sum);
        if (sum == expected_sum) {
            printf("✓ Reduction test PASSED\n");
        } else {
            printf("✗ Reduction test FAILED\n");
        }
        fflush(stdout);
    }
    
    MPI_Barrier(MPI_COMM_WORLD);
    
    // Gather test - collect hostnames
    char all_hostnames[MAX_HOSTNAME * world_size];
    MPI_Gather(hostname, MAX_HOSTNAME, MPI_CHAR, 
               all_hostnames, MAX_HOSTNAME, MPI_CHAR, 
               0, MPI_COMM_WORLD);
    
    if (world_rank == 0) {
        printf("\n=== Node Distribution ===\n");
        int node_counts[world_size];
        char unique_nodes[world_size][MAX_HOSTNAME];
        int num_unique_nodes = 0;
        
        for (int i = 0; i < world_size; i++) {
            char* node = &all_hostnames[i * MAX_HOSTNAME];
            
            // Check if this node is already in the list
            int found = 0;
            for (int j = 0; j < num_unique_nodes; j++) {
                if (strcmp(unique_nodes[j], node) == 0) {
                    node_counts[j]++;
                    found = 1;
                    break;
                }
            }
            
            if (!found) {
                strcpy(unique_nodes[num_unique_nodes], node);
                node_counts[num_unique_nodes] = 1;
                num_unique_nodes++;
            }
        }
        
        printf("Processes distributed across %d node(s):\n", num_unique_nodes);
        for (int i = 0; i < num_unique_nodes; i++) {
            printf("  %s: %d processes\n", unique_nodes[i], node_counts[i]);
        }
        printf("\n");
        fflush(stdout);
    }
    
    // Final synchronization
    MPI_Barrier(MPI_COMM_WORLD);
    
    if (world_rank == 0) {
        printf("=== All MPI Tests Completed Successfully ===\n");
        fflush(stdout);
    }
    
    // Finalize MPI
    MPI_Finalize();
    return 0;
}

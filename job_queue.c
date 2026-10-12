#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <pthread.h>
#include <stdbool.h>

#include "job_queue.h"


int job_queue_init(struct job_queue *job_queue, int capacity) {
  job_queue->head = 0;
  job_queue->tail = 0;
  job_queue->current_capacity = 0;
  job_queue->capacity = capacity;
  job_queue->queue = calloc(capacity, sizeof(void*));
  pthread_mutex_init(&job_queue->mutex, NULL);
  pthread_cond_init(&job_queue->not_full, NULL);
  pthread_cond_init(&job_queue->not_empty, NULL);
  pthread_cond_init(&job_queue->empty, NULL);

  job_queue->is_destroyed = 0;

  return 0;
}


int job_queue_destroy(struct job_queue *job_queue) {
  pthread_mutex_lock(&job_queue->mutex);
  while (job_queue->current_capacity > 0) {
    pthread_cond_wait(&job_queue->empty, &job_queue->mutex);
  }
  job_queue->is_destroyed = 1;

  pthread_cond_broadcast(&job_queue->not_empty);
  pthread_cond_broadcast(&job_queue->not_full);
  free(job_queue->queue);
  pthread_mutex_unlock(&job_queue->mutex);
  return 0;
}

// https://www.geeksforgeeks.org/c/queue-in-c/ Reference for queue implementation in C
int job_queue_push(struct job_queue *job_queue, void *data) {
  pthread_mutex_lock(&job_queue->mutex);
  
  if (job_queue->is_destroyed) {
    pthread_mutex_unlock(&job_queue->mutex);
    return -1;
  }

  while (job_queue->tail == job_queue->capacity)
    {
      pthread_cond_wait(&job_queue->not_full, &job_queue->mutex);
    }
    job_queue->queue[job_queue->tail] = data;
    job_queue->tail = (job_queue->tail + 1) % job_queue->capacity;
    job_queue->current_capacity++;

    pthread_cond_signal(&job_queue->not_empty);


    pthread_mutex_unlock(&job_queue->mutex);
  return 0;
}

int job_queue_pop(struct job_queue *job_queue, void **data) {
  pthread_mutex_lock(&job_queue->mutex);

  if (job_queue->is_destroyed) {
    pthread_mutex_unlock(&job_queue->mutex);
    return -1;
  }

  while (job_queue->head == job_queue->tail)
  {
    pthread_cond_wait(&job_queue->not_empty, &job_queue->mutex);
  }

  if (job_queue->current_capacity == 0) {
    pthread_mutex_unlock(&job_queue->mutex);
    return -1;
  }
  *data = job_queue->queue[job_queue->head];
  job_queue->head = (job_queue->head + 1) % job_queue->capacity;
  job_queue->current_capacity--;

  if (job_queue->current_capacity == 0) {
    pthread_cond_signal(&job_queue->empty);
  }

  pthread_cond_signal(&job_queue->not_full);

  pthread_mutex_unlock(&job_queue->mutex);
  return 0;
}

